# reviews

Code reviews of this fork and the replies to them, kept because the reasoning is more useful than the
verdicts.

`2026-08-14-review-1.md` found two real bugs. A window that was both sticky and parked in a
scratchpad got dragged back out on the next refresh, because the guard against moving *into* a
scratchpad said nothing about moving *out of* one. And `window-hints` sorted workspaces with a
comparator that ignored its right operand, which isn't a strict weak ordering and which Swift's sort
is entitled to trap on.

`2026-08-14-response-1.md` accepts both and pushes back on the other two findings: one proposed patch
was a no-op that also wouldn't compile, and the other would have rejected Turkish snapshot names.

`2026-08-14-review-2.md` landed the best finding of the three: the fork was still runtime-labelled as
upstream AeroSpace in bundle id, config path, socket and state directory, so the two would collide.
That's what prompted the rename to `AeroSpace Next`. It also correctly rebutted the claim that
duplicate windows couldn't be told apart, since window ids are exact within a session.

It was wrong about one thing worth recording, because the mistake is easy to repeat. It reported that
`swift-test.sh` was a false green running zero tests. XCTest was running the whole time; the script's
own `sed` filters delete every passing line, including the final `Executed N tests` summary, so a
green run showed nothing but the Swift Testing runner's "0 tests in 0 suites". The script now prints
the count back so a green run says what it was green on.

The pattern across all three: static review caught type-level and ordering bugs that testing missed,
and missed every bug that came from macOS handing focus back to the app at an awkward moment. Those
only ever showed up by running it.
