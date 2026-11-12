#!/bin/sh
# Builds what the tests need, imports the project (builds the class_name cache), then runs tests/run.gd in
# several godot processes at once, each with its own user:// (tools/run_tests.py).
# Usage: ./run_tests.sh                 all tests
#        ./run_tests.sh -- name         only tests whose "file:method" contains name
#        ./run_tests.sh -j 1 [-- name]  in one godot process (default: TEST_JOBS, else the cores less 2)
# TEST_TIMEOUT: seconds one process may take (default 600; over it, it is stopped and its test named).
set -e
cd "$(dirname "$0")"
case $(uname -s) in
Darwin) platform=macos lib=libclassichs_godot.macos.dylib ;;
Linux) platform=linux lib=libclassichs_godot.linux.x86_64.so ;;
*) platform=windows lib=classichs_godot.windows.x86_64.dll ;;
esac
[ -f "rules/bin/$lib" ] || { echo "rules/bin/$lib is missing: build the rules engine first (tools/build_rules.sh $platform)" >&2; exit 1; }
tools/build_packs.sh  # res://packs/*.cardpack: the game reads its cards from them
tools/fetch_webrtc.sh  # the WebRTC plugin of the native builds (code play)
python3 tools/arch_page.py --check >/dev/null  # the site's architecture page points at real lines (else the release's site fails)
godot --headless --log-file "$PWD/build/import.log" --path . --import >/dev/null 2>&1 || true
exec python3 tools/run_tests.py "$@"
