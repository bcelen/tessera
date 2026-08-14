#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

log="$(mktemp -t aerospace-swift-test)"

# The sed filters below drop every passing XCTest line, including the final "Executed N tests"
# summary. On a green run that leaves only the Swift Testing runner's "0 tests in 0 suites", which
# reads as though nothing ran at all. XCTest does run; the count is printed back from the
# unfiltered log so a green run says how many tests it was green on.
if swift test 2>&1 \
    | tee "$log" \
    | sed -E '/^Test (Suite|Case).*(started|passed)/d' \
    | sed -E '/^[[:space:]]+Executed.*with 0 failures/d' \
    | sed -E '/ [[:digit:]]+(:[[:digit:]]+)+/s/:/;/g' # Replace colons with semicolons in dates to avoid treating these lines as files in vim
then
    grep -E "Executed [0-9]+ tests?" "$log" | tail -1 | sed -E 's/^[[:space:]]+//' || true
    rm -f "$log"
    echo "✅ Swift tests have passed successfully"
else
    rm -f "$log"
    echo "❌ Swift tests have failed"
    exit 1
fi
