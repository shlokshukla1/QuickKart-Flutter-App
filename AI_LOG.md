# AI usage log

Tools used: Claude Code (Claude Opus 5.5) in VS Code on Windows; Flutter 3.47 CLI to run `flutter analyze` / `flutter test` / `flutter run -d chrome`.

## Significant prompts (5–10)

| # | What I asked (summary is fine) | What I did with the answer |
|---|---|---|
| 1 | "Read all files, change nothing, explain what the app does and which bugs exist and why." | Got a map of the architecture and a list of ~15 suspected bugs plus a "looks wrong but is correct" list. I checked each one against BUSINESS_RULES / API_CONTRACT and the mock server code (e.g. the server uses `>=` for free delivery, sends `mrp: null` for legacy products) before accepting it. |
| 2 | "How do I run this?" / install Flutter | Flutter wasn't on PATH; set it up in `C:\src\flutter`, ran the app in Chrome from a separate copy so the repo didn't get platform folders. |
| 3 | "Fix only one bug (QK-101) and explain before/after and which file." | Reviewed the diff: `decrement` / `remove` / `removeCoupon` never saved. Kept it as the first fix commit. |
| 4 | "Fix all bugs, add a short comment at each change, give me a table of what changed where." | Accepted the fixes only after a verification test for each one passed on the fixed code **and failed on the original code** (checked with `git archive` of the starting commit). |
| 5 | "Make the test-first commits for every bug." | Each bug has its own test file under `test/bugs/`; the history has `test:` before `fix:` for all 15. I confirmed each test fails before its fix (e.g. double-tap test still failed after the idempotency fix, proving it is a separate bug). |
| 6 | "Implement CartReconciler.reconcile and safe checkout." | Reviewed the contract line by line against the generated code (all data fetched before touching the cart; chunks of 50; coupon refresh vs removal). Added 16 reconciler tests and 10 checkout tests. |
| 7 | "Implement remote config caching, live updates, version gate, kill switch, server-driven home." | Checked that `AppConfigController` works in a bare `ProviderContainer` (hidden-test requirement) and that the listener count goes back to 0 on dispose. Added widget tests for force/optional update, store closing on the cart screen and bad `home_sections`. |
| 8 | "Fill BUGS.md / DECISIONS.md / AI_LOG.md in place." | Edited for accuracy (commit SHAs, steps that actually reproduce in Dev tools). |

## When the AI was wrong or misleading (at least 3)

### 1.
- **What it suggested:** "All 17 verification tests fail on the original code, so every bug is proven."
- **Why it was wrong:** 13 of the 17 failed for the *same* reason: the test helper loaded products through the catalog, which crashed on the legacy-product bug (`type 'Null' is not a subtype of type 'num'`). Those tests proved nothing about their own bug.
- **How I noticed:** Printed the actual failure message of every test instead of just the pass/fail count.
- **What I did instead:** Build test products from the server's admin snapshot (`test/helpers/catalog_helpers.dart`) so cart/checkout tests don't depend on catalog parsing; re-ran on the original code and every test now fails with its own assertion (e.g. "Expected 1 order, Actual 2").

### 2.
- **What it suggested:** Reconcile the cart before *every* order attempt, including a retry after a timeout.
- **Why it was wrong:** If the lost order bought the last unit, the retry's reconciliation sees stock 0 and tells the user their item is "out of stock" – about their own, already created, order – instead of returning it.
- **How I noticed:** Walked through the "Lose next" scenario with stock = 1 while reviewing the checkout flow.
- **What I did instead:** If a pending idempotency key matches the current cart, re-send that exact request first; reconcile only for a new attempt. Covered by `lost response on the last item in stock: retry returns that order`.

### 3.
- **What it suggested:** Fix the `CategoryScreen` leak by keeping its own `remoteUpdates` subscription and cancelling it in `dispose`.
- **Why it was wrong:** Correct for the bug alone, but once `AppConfigController` subscribed to live updates (Feature 2), the screen's extra listener caused a second config fetch on every publish.
- **How I noticed:** While implementing live updates in the controller, reading the screen code showed both would call `refresh()` on each publish.
- **What I did instead:** Screen became a plain `ConsumerWidget` that only watches the controller; the bug test (`configListenerCount` returns to the baseline) still passes.

### 4.
- **What it suggested:** A regression test "refresh during loadMore does not duplicate" as proof for BUG-11, and a widget test that used a provider name that doesn't exist.
- **Why it was wrong:** The refresh test also passes on the old code (it is a regression check, not a reproduction), and the made-up provider name didn't compile.
- **How I noticed:** Ran the bug tests on the original code (that test passed there) and `flutter analyze` flagged the undefined name.
- **What I did instead:** Kept the concurrent-`loadMore` test as the actual proof (16 items instead of 12 on the old code) and documented the other one as a regression test; fixed the import.

## What I would NOT trust an AI with in this codebase, and why

- **Deciding what is a bug.** Several things look wrong but are correct (percent coupons rounding down, 501 not retried, no cache fallback on 4xx). Only BUSINESS_RULES and the server code decide; the AI happily "fixes" plausible-looking code.
- **Money and idempotency logic without tests.** One wrong comparison (`>` vs `>=`) or a retry without a key costs real customers money; every such change needs a failing-first test.
- **"It passes" claims.** I only trust test results I ran myself, and I check *why* a test fails before calling it proof.
- **The mock server / contract boundaries.** It must not edit `lib/mock_server/` or rename public-contract symbols to make tests pass.
