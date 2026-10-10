#!/bin/sh
# Imports the project (builds the class_name cache), then runs tests/run.gd.
# Usage: ./run_tests.sh            all tests
#        ./run_tests.sh -- name    only tests whose "file:method" contains name
set -e
cd "$(dirname "$0")"
godot --headless --path . --import >/dev/null 2>&1 || true
exec godot --headless --path . --script res://tests/run.gd "$@"
