# Step logging for the build, release and deploy scripts (POSIX sh, sourced: . tools/log.sh).
#   log_init <name> <repo root> [nofile]   once, at the start (installs the EXIT trap)
#   log_steps <total>; log_step "Title" [number]; log_info "..."; log_warn "..."; log_fail "reason"
# A step prints "[17:42:05] ▶ 3/9 Title"; when the next one starts or the script ends, "✔ 3/9 done in 2m14s".
# A failure (set -e, log_fail, Ctrl-C) prints the step it stopped in, the failing command (bash) and the
# last lines of the output, and the script exits non-zero.
# log_init tees everything the script prints to build/logs/<name>-<UTC time>.log (CHS_LOG_DIR to change)
# and prints its path at the start and the end. Colours only on a terminal (and never in the file).
# A script started by another one writes into that one's log (CHS_LOG_FILE is set), indented; under CI
# (CI=true) or with "nofile" (the light scripts: build_packs.sh, build_rules.sh) there is no log file.
# log_watch_run <GitHub Actions run id> waits for a run, printing its jobs (see below).

LOG_N=0 LOG_TOTAL= LOG_STEP= LOG_STEP_T0= LOG_DIRECT= LOG_LIGHT= LOG_TEE= LOG_REASON= LOG_FAILED_CMD= LOG_ON_EXIT=
LOG_T0=$(date +%s)

log_now() { date +%s; }
log_dur() {  # seconds -> 40s, 2m14s, 1h05m
	if [ "$1" -ge 3600 ]; then printf '%dh%02dm' $(($1 / 3600)) $(($1 % 3600 / 60))
	elif [ "$1" -ge 60 ]; then printf '%dm%02ds' $(($1 / 60)) $(($1 % 60))
	else printf '%ds' "$1"; fi
}
log_size() {  # bytes -> 57.3 MB
	awk -v b="$1" 'BEGIN { b += 0; if (b >= 1e9) printf "%.2f GB", b / 1e9; else if (b >= 1e6) printf "%.1f MB", b / 1e6;
		else if (b >= 1e3) printf "%.0f KB", b / 1e3; else printf "%d B", b }'
}
log_fsize() { log_size "$(wc -c < "$1")"; }  # a file's size

_log() {  # colour (ANSI code or empty), text
	if [ "${CHS_LOG_COLOR:-}" = 1 ] && [ -n "$1" ]; then printf '\033[%sm%s\033[0m\n' "$1" "$2"; else printf '%s\n' "$2"; fi
	[ -z "$LOG_DIRECT" ] || printf '%s\n' "$2" >> "$CHS_LOG_FILE"
}
_log_at() { printf '%s[%s]' "$LOG_PFX" "$(date +%H:%M:%S)"; }
_log_num() { [ -z "$LOG_TOTAL" ] || printf '%s/%s ' "$LOG_N" "$LOG_TOTAL"; }

log_info() { _log '' "$(_log_at)   $*"; }
log_warn() { _log '33' "$(_log_at) ! $*"; }
log_steps() { LOG_TOTAL=$1; }
log_step() {  # title [number]: ends the step before, starts this one
	log_done
	LOG_N=${2:-$((LOG_N + 1))}
	LOG_STEP=$1
	LOG_STEP_T0=$(log_now)
	_log '1;36' "$(_log_at) ▶ $LOG_LABEL$(_log_num)$1"
}
log_done() {  # ends the current step: "✔ 3/9 done in 2m14s"
	[ -n "$LOG_STEP" ] || return 0
	_log '32' "$(_log_at) ✔ $LOG_LABEL$(_log_num)done in $(log_dur $(($(log_now) - LOG_STEP_T0)))"
	LOG_STEP=
}
log_bad() {  # ends the current step as failed, the script goes on: "✘ 3/9 failed after 40s: reason"
	_log '31' "$(_log_at) ✘ $LOG_LABEL$(_log_num)failed after $(log_dur $(($(log_now) - LOG_STEP_T0))): $*"
	LOG_STEP=
}
log_fail() { LOG_REASON=$*; exit 1; }  # stops the script with a reason

log_init() {  # name, repo root, [nofile]
	LOG_NAME=$1
	[ "${3:-}" != nofile ] || LOG_LIGHT=1
	if [ -n "${CHS_LOG_DEPTH:-}" ]; then
		CHS_LOG_DEPTH=$((CHS_LOG_DEPTH + 1))
		LOG_LABEL="$1: "
	else
		CHS_LOG_DEPTH=0
		LOG_LABEL=
		if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then CHS_LOG_COLOR=1; else CHS_LOG_COLOR=0; fi
	fi
	LOG_PFX=$(printf "%$((CHS_LOG_DEPTH * 2))s" '')
	export CHS_LOG_DEPTH CHS_LOG_COLOR
	trap _log_exit EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	if [ -n "${BASH_VERSION:-}" ]; then  # bash: remember the command set -e stops at
		set -o errtrace
		trap 'LOG_FAILED_CMD=$BASH_COMMAND' ERR
	fi
	if [ -z "${CHS_LOG_FILE:-}" ] && [ -z "$LOG_LIGHT" ] && [ "${CI:-}" != true ]; then
		_d=${CHS_LOG_DIR:-$2/build/logs}
		mkdir -p "$_d"
		CHS_LOG_FILE=$_d/$1-$(date -u +%Y%m%d-%H%M%SZ).log
		_fifo=$_d/.$1-$$.fifo
		LOG_TEE_DONE=$_d/.$1-$$.done
		rm -f "$_fifo" "$LOG_TEE_DONE"
		mkfifo "$_fifo"
		# the screen gets the colours, the file plain text; Ctrl-C stops the script, not this copy
		( trap '' INT TERM
		  awk -v f="$CHS_LOG_FILE" '{ print; fflush(); l = $0; gsub(/\033\[[0-9;]*m/, "", l); print l >> f; fflush(f) }'
		  : > "$LOG_TEE_DONE" ) < "$_fifo" &
		LOG_TEE=$!
		exec 8>&1 9>&2 > "$_fifo" 2>&1
		rm -f "$_fifo"
		export CHS_LOG_FILE PYTHONUNBUFFERED=1
		_log '1' "$(_log_at) $1: log in $CHS_LOG_FILE"
	fi
}

_log_exit() {
	_st=$?
	trap - EXIT
	set +e
	if [ -n "$LOG_TEE" ]; then  # back to the screen; let the copy finish writing the file
		exec 1>&8 2>&9 8>&- 9>&-
		_i=0
		while [ ! -e "$LOG_TEE_DONE" ] && [ $_i -lt 50 ]; do sleep 0.1; _i=$((_i + 1)); done
		rm -f "$LOG_TEE_DONE"
		LOG_DIRECT=1
	fi
	_total=$(log_dur $(($(log_now) - LOG_T0)))
	if [ "$_st" = 0 ]; then
		log_done
		[ -n "$LOG_LIGHT" ] || _log '1;32' "$(_log_at) ✔ $LOG_NAME finished in $_total"
	else
		if [ -n "$LOG_DIRECT" ]; then  # the output since the failed step started
			_tail=$(awk -v h="▶ $LOG_LABEL$(_log_num)$LOG_STEP" 'index($0, h) { n = 0; next } { l[++n] = $0 }
				END { for (i = (n > 20 ? n - 19 : 1); i <= n; i++) print "    | " l[i] }' "$CHS_LOG_FILE")
			[ -z "$_tail" ] || { _log '' "$(_log_at) the last lines of the output:"; printf '%s\n' "$_tail"; }
		fi
		_where=${LOG_STEP:+ at $(_log_num)$LOG_STEP}
		_why=${LOG_REASON:-exit $_st${LOG_FAILED_CMD:+, the command: $LOG_FAILED_CMD}}
		[ "$_st" != 130 ] || _why="stopped (Ctrl-C)"
		_log '1;31' "$(_log_at) ✘ $LOG_NAME failed$_where after $(log_dur $(($(log_now) - ${LOG_STEP_T0:-$LOG_T0}))): $_why"
		_log '31' "$(_log_at) ✘ $LOG_NAME failed after $_total"
	fi
	[ -z "$LOG_DIRECT" ] || _log '1' "$(_log_at) $LOG_NAME: log in $CHS_LOG_FILE"
	eval "$LOG_ON_EXIT"
	exit "$_st"
}

# log_watch_run <run id> [poll seconds]: waits for a GitHub Actions run to complete. Prints its URL, the
# table of its jobs (name, status or conclusion, time) whenever a job's state changes, and every minute
# "still waiting: <the unfinished jobs>". Sets LOG_RUN_CONCLUSION (success, failure, cancelled, ...).
LOG_RUN_PY='
import json, re, sys, datetime as d
r = json.load(sys.stdin)
now = d.datetime.now(d.timezone.utc)
def t(s):
    return None if not s or s.startswith("0001") else d.datetime.fromisoformat(s.replace("Z", "+00:00"))
def dur(s):
    s = int(s)
    return "%dh%02dm" % (s // 3600, s % 3600 // 60) if s >= 3600 else "%dm%02ds" % (s // 60, s % 60) if s >= 60 else "%ds" % s
rows, sig, busy = [], [], []
for j in r["jobs"]:
    j["name"] = re.sub(r" \(([^,)]*).*$", r" \1", j["name"])  # rust (macos-15, macos, ...) -> rust macos-15
    st = j["conclusion"] or j["status"]
    a, b = t(j.get("startedAt")), t(j.get("completedAt"))
    el = dur(((b or now) - a).total_seconds()) if a else "-"
    rows.append((j["name"], st, el))
    sig.append(j["name"] + "=" + st)
    if j["status"] != "completed":
        busy.append("%s %s %s" % (j["name"], st, el))
print("STATUS", r["status"], r["conclusion"] or "")
print("SIG", ";".join(sig))
print("BEAT", ", ".join(busy) or "-")
w = max([len(x[0]) for x in rows] + [4])
for n, s, e in rows:
    print("ROW %s  %s %s" % (n.ljust(w), s.ljust(12), e))
'
log_watch_run() {
	_run=$1 _poll=${2:-15} _sig=x _beat=$(log_now) _w0=$(log_now)
	log_info "run $_run: $(gh run view "$_run" --json url --jq .url 2>/dev/null || echo '?')"
	while :; do
		if ! _out=$(gh run view "$_run" --json status,conclusion,jobs | python3 -c "$LOG_RUN_PY" 2>&1); then
			log_warn "could not read run $_run, trying again in 30s: $(printf '%s' "$_out" | tail -n 1)"
			sleep 30
			continue
		fi
		_state=$(printf '%s\n' "$_out" | sed -n 's/^STATUS //p')
		_s=$(printf '%s\n' "$_out" | sed -n 's/^SIG //p')
		if [ "$_s" != "$_sig" ]; then
			_sig=$_s _beat=$(log_now)
			log_info "run $_run (${_state% }), $(log_dur $(($(log_now) - _w0))) into this wait:"
			printf '%s\n' "$_out" | sed -n "s/^ROW /$LOG_PFX             /p"
		elif [ $(($(log_now) - _beat)) -ge 60 ]; then
			_beat=$(log_now)
			log_info "still waiting: $(printf '%s\n' "$_out" | sed -n 's/^BEAT //p')"
		fi
		case $_state in completed\ *) LOG_RUN_CONCLUSION=${_state#completed }; return 0 ;; esac
		sleep "$_poll"
	done
}
