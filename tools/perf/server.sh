#!/bin/sh
# The performance harness's game server: server/target/release/classichs-server on 127.0.0.1:$1 with a
# database and store of its own in $2 (made empty; never the real server/classichs.db or server/store),
# Classic as the default game. Meanwhile it moves every full tournament's start to 5 s from now (the
# server takes a start 11 minutes ahead at least; the harness's driver waits for this) and keeps the log in
# $2/server.log. Stop: kill this script's process group (tools/perf/stop.sh does).
# Usage: tools/perf/server.sh PORT DIR
set -e
cd "$(dirname "$0")/../.."
PORT=$1
DIR=$2
[ -n "$PORT" ] && [ -n "$DIR" ] || { echo "usage: tools/perf/server.sh PORT DIR" >&2; exit 1; }
[ "$PORT" != 7377 ] || { echo "7377 is the owner's own server" >&2; exit 1; }
rm -rf "$DIR"
mkdir -p "$DIR/store"
server/target/release/classichs-server --db "$DIR/perf.db" --store-dir "$DIR/store" --packs-dir packs \
	--default-pack classic --listen "127.0.0.1:$PORT" >"$DIR/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT INT TERM
while kill -0 $SERVER 2>/dev/null; do
	if [ -f "$DIR/perf.db" ]; then
		NOW=$(python3 -c 'import time; print(int(time.time() * 1000))')
		sqlite3 -cmd ".timeout 3000" "$DIR/perf.db" "UPDATE tournaments SET start_at = $NOW + 5000 WHERE status = 'open'
			AND start_at > $NOW + 60000 AND (SELECT COUNT(*) FROM t_entrants e WHERE e.tournament = tournaments.id) >= max_players;" \
			2>/dev/null || true
	fi
	sleep 3
done
