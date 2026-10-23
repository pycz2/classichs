#!/bin/bash
# Stops tools/gen_art_styles.py (and its codex exec children) when the weekly Codex limit is
# MAX_USED percent used or more (default 90, so less than 10 % is left). It reads the limit
# through `codex app-server` (account/rateLimits/read, free) every 3 minutes, and also stops
# the generation when the limit cannot be read 5 times in a row. Exits when the generation ends.
# Usage: tools/codex_guard.sh [MAX_USED]
C=${CODEX:-/Applications/ChatGPT.app/Contents/Resources/codex}
MAX=${1:-90}
used() {
  (printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"ratecheck","version":"0.1"}}}' \
    '{"jsonrpc":"2.0","method":"initialized"}' '{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}'; sleep 8) \
  | "$C" app-server 2>/dev/null | python3 -c 'import sys,json
for l in sys.stdin:
    m=json.loads(l)
    if m.get("id")==2: print(int(m["result"]["rateLimits"]["primary"]["usedPercent"])); break' 2>/dev/null
}
stop() {
  for p in $(pgrep -f "[g]en_art_styles.py"); do kids=$(pgrep -P "$p"); kill "$p"; [ -n "$kids" ] && kill $kids; done
  echo "STOPPED: $1"; exit 0
}
fails=0
while pgrep -f "[g]en_art_styles.py" >/dev/null; do
  u=$(used); echo "$(date '+%m-%d %H:%M') used=${u:-?}%"
  if [ -z "$u" ]; then
    fails=$((fails + 1)); [ $fails -ge 5 ] && stop "the weekly Codex limit could not be read 5 times in a row"
  else
    fails=0; [ "$u" -ge "$MAX" ] && stop "weekly Codex limit used $u% (>= $MAX%)"
  fi
  sleep 180
done
echo "generation finished, guard exits"
