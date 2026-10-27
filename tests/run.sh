#!/bin/sh
# signal test runner.
#
# Follows the convention of Salam's own test corpus (tests/en/stdlib): every
# tests/<name>.salam is a program that asserts with std/testing and ends with
# `ret testing.Summary()`, and tests/<name>.out is its golden stdout. A test
# passes when it builds, exits 0, and its stdout matches the golden file
# byte for byte. Failed assertions are reported on stderr by std/testing.
#
# Usage: tests/run.sh [name ...]      (default: every tests/*.salam)
# Env:   SALAM=path/to/salam          (default: salam on PATH)
#        TEST_TIMEOUT=seconds          (default: 30; bound on each test run)
#        SALAM_BACKEND=llvm|c          (default: the compiler's own backend)
#
# SALAM_BACKEND is expanded unquoted, so only one word works: llvm or c.

set -u

SALAM="${SALAM:-salam}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
SALAM_BACKEND="${SALAM_BACKEND:-}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/tests${SALAM_BACKEND:+-$SALAM_BACKEND}"
mkdir -p "$OUT"

# Salam links with the host toolchain on macOS; pin the deployment target to
# the running OS so the linker does not warn about mismatched versions.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
    export MACOSX_DEPLOYMENT_TARGET
fi

if [ "$#" -gt 0 ]; then
    names="$*"
else
    names=$(cd "$ROOT/tests" && ls *.salam | sed 's/\.salam$//')
fi

pass=0
fail=0
for name in $names; do
    src="$ROOT/tests/$name.salam"
    want="$ROOT/tests/$name.out"
    bin="$OUT/$name"
    got="$OUT/$name.stdout"

    if ! "$SALAM" build "$src" --output="$bin" ${SALAM_BACKEND:+--backend=$SALAM_BACKEND} --log-level=warn; then
        echo "FAIL $name (build)"
        fail=$((fail + 1))
        continue
    fi
    # Tests never read the terminal; give them an empty stdin so a test that
    # accidentally does cannot hang the run. A watchdog bounds the run as
    # well: a hung test must fail fast, not stall the whole suite (a blocked
    # SIGWINCH wait once hung CI for twenty minutes).
    "$bin" < /dev/null > "$got" &
    pid=$!
    ( sleep "$TEST_TIMEOUT"; kill -9 "$pid" 2>/dev/null ) &
    watchdog=$!
    wait "$pid"
    code=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    if [ "$code" -eq 137 ]; then
        echo "FAIL $name (timeout after ${TEST_TIMEOUT}s)"
        fail=$((fail + 1))
    elif [ "$code" -ne 0 ]; then
        echo "FAIL $name (exit $code)"
        fail=$((fail + 1))
    elif ! diff -u "$want" "$got"; then
        echo "FAIL $name (output differs from $name.out)"
        fail=$((fail + 1))
    else
        echo "ok   $name"
        pass=$((pass + 1))
    fi
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
