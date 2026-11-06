# Decisions & trade-offs

> Short and specific beats long and generic. Bullet points are fine.

## 1. Cart reconciliation policy (Feature 1)

- **When does reconciliation run, and why there?**
  - **When the cart screen opens** (`CartReviewController.syncWithServer`): the user sees changes *before* deciding to pay, and a cart built offline is synced as soon as it is looked at online. Silent if offline (cart untouched).
  - **Before every order** (`CheckoutController.placeOrder`): the only point where it *must* be correct; prices can drift between opening the cart and tapping the button.
  - **After a 409/422 from `POST /v1/orders`** (`PRICE_CHANGED`, `INSUFFICIENT_STOCK`, `QUANTITY_LIMIT`, `PRODUCT_UNAVAILABLE`, `COUPON_INVALID`, `TOTAL_MISMATCH`): something changed in the window between our check and the order. `TOTAL_MISMATCH` also refreshes remote config (fee/threshold may have changed).
  - Not on every app start / connectivity change: it costs a batch request + coupon call, and the two points above already guarantee correctness.
- **What does the user see for each kind of change?** A card at the top of the cart lists every change in a full sentence with the product name (names come from the cart *before* the change, so removed items are still named), plus a snackbar telling them to check and tap again:
  - price up: "🍌 Robusta Banana: price went up from ₹49 to ₹59." → **review required** (order not placed).
  - price down: applied silently at checkout (BUSINESS_RULES §5); if found when opening the cart it is shown as "Good news, your cart got cheaper".
  - out of stock: "… is out of stock and was removed." → review.
  - quantity reduced: "… only 1 available, so your quantity went from 2 to 1." → review.
  - discontinued: "… is no longer sold and was removed." → review.
  - coupon removed: "Coupon FLAT50 has expired and was removed." / "… is no longer valid …" → review.
  - Acknowledging = tapping *Got it* or tapping *Place order* again (which re-reconciles; if nothing changed again, the order goes through).
- **What happens to out-of-stock / discontinued items?** Removed from the cart (the contract requires the returned cart to be orderable and BUSINESS_RULES says they are never ordered), but **not silently**: they stay listed by name in the review card until acknowledged, so the user knows exactly what to replace. I chose not to keep "ghost" lines in the cart because they would complicate totals, persistence and the hidden-test contract for little benefit at this size.
- **Offline-built carts:** cart is persisted on every change; nothing is checked while offline. On the first online cart-open or checkout it is reconciled against the server like any other cart. Offline checkout returns "You're offline. Your cart is saved…", never a crash or a generic error.
- **Alternatives considered and rejected:**
  - Trust the server's 409 only (no reconciliation before ordering): needs a failed POST to find each problem, and the server stops at the *first* failing check, so the user would discover issues one at a time.
  - Auto-accept everything and show a toast "cart updated": violates "never charged an amount they have not seen".
  - Reconcile per product with `GET /products` pages: more requests; the batch endpoint exists for this.
  - Ignoring a partial batch result: rejected by contract – all data is fetched before the cart is touched, so any network error throws and nothing is changed.

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?** (key generation, lifetime, storage)
  - A UUID v4 `Idempotency-Key` per order attempt, persisted in `KeyValueStore` (`checkout.pending_order.v1`) together with a fingerprint = the exact JSON body.
  - Reused when the same body is sent again: the automatic retry after a timeout, a second tap, or a tap after an app restart. A changed cart gets a new key (otherwise the server would answer `IDEMPOTENCY_KEY_REUSED`).
  - Deleted after success or after a definite 4xx answer (order certainly not created). Kept after timeout / offline / 5xx.
  - If a key for the *current* cart is pending, the request is **re-sent before reconciling**: the server answers with the original order. Reconciling first would be wrong here: the lost order already consumed the stock, so the user would be told "out of stock" about their own order (`test/features/checkout_test.dart` covers this).
  - Double tap: `placeOrder` returns the in-flight `Future`; the button is disabled while placing.
- **What does the user see on timeout / lost response?** "We could not confirm your order. It may have been placed, so please check My orders. Tapping "Place order" again is safe: it will not create a second order." Tapping again returns the original order (success screen) – never a second one.
- **Edge cases you handled:**
  - store known closed → `CheckoutFailure(store_closed_message)` without any request; store closed on the server but not yet known (`503 STORE_CLOSED`) → config refreshed, banner appears, honest message;
  - offline / slow network *before* the order request (reconciliation failed) → "not placed, try again" is said only there, because then it is certain;
  - 5xx on the order → key kept, "you won't be charged twice";
  - the user edits the cart while reconciliation runs → result discarded instead of overwriting their edit;
  - coupon below its minimum → order goes through without the code (BUG-9);
  - only price drops → applied silently and the order continues.
- **Edge cases you know you did NOT handle:**
  - Response lost, then the cart (or delivery fee config) changes before the next tap → new fingerprint → new key → a second order is possible. The message tells the user to check *My orders* first; a full fix would query recent orders before sending a new key.
  - Pending key is kept forever if the user never retries (harmless, small).
  - The server checks `store_open` *before* idempotency, so if the store closes right after a lost response, the retry can't fetch the original order until it reopens.

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:** `ConfigRepository.load()` fetches `/v1/config`; on success the raw `values` are persisted (`remote_config.v1`); on *any* failure (offline, timeout, 5xx, malformed body) it returns the last known good config, else `AppConfig.defaults()`. It never throws. At startup `main.dart` hydrates from the cache immediately and refreshes in the background, so the first frame never waits for a slow network (first launch has no cache, so it waits for one fetch, which falls back to defaults offline).
- **How live updates propagate, and how you avoid leaks:** `AppConfigController.build()` subscribes to `ConfigRepository.remoteUpdates` and refetches on each event; `ref.onDispose(sub.cancel)` releases it (test checks `configListenerCount` goes back to 0). Works in a bare `ProviderContainer`. A refresh counter drops stale responses. Every screen just `watch`es the controller (the old per-screen listener in `CategoryScreen` was the leak in BUG-12).
- **Force / optional update UX:** `UpdatePolicy.evaluate` (numeric, segment-wise, malformed → `none`). `UpdateGate` wraps the navigator via `MaterialApp.builder`, so it covers every route and reacts mid-session:
  - required → the whole app is replaced by a full-screen "Update required" page with *Update now* (opens `update_url`; if it can't be opened the URL is copied and shown). No back, no close. If ops roll the config back, the app comes back.
  - optional → a card at the bottom with *Update* / *Later*. *Later* stores the dismissed `latest_version`; the card returns only for a newer `latest_version`.
- **Store closed UX:** red banner with `store_closed_message` on Home and in the cart (live). Browsing and cart editing still work; *Place order* is disabled and reads "Store closed"; `placeOrder` refuses without a request.
- **Server-driven home: robustness to bad config:** `HomeLayout.parse` ignores unknown ids, non-strings and duplicates, and falls back to `[categories, all_products]` for null/malformed/non-array/empty. Rendering: sections in config order; the infinite product grid is in the middle of the same scroll view, sections after `all_products` render as footers. Missing/malformed banner → section skipped; banner colour falls back to orange; deals that fail or are empty → hidden. Categories are cached so the home works offline.

## 4. Feature 3 (if attempted)

Not attempted. I prioritised making Parts A–C solid and tested; the brief says broken optional work costs points.

## 5. Other decisions

- Packages added (and why):
  - `url_launcher` – the standard way to open `update_url` (store/download page) from the force-update screen; with a clipboard fallback if it fails.
  - (`uuid` was already a dependency; used for idempotency keys.)
- Refactors you made to the existing code (and why):
  - `CartController._commit` + a write queue: one place that updates state and persists (fixes BUG-1 and BUG-15 together).
  - `OrderApi.buildBody` is static so the checkout fingerprints exactly the body that is sent.
  - `ApiClient` lost its response cache and clock parameter (BUG-2).
  - `PaginatedCatalogView` got `footerSlivers` / `onRefresh` so the home layout can put sections after the grid and refresh them too.
  - `CategoryScreen` became a plain `ConsumerWidget`.
  - `CatalogRepository.getCategories` is network-first with an offline cache.
  - Public contract (ARCHITECTURE.md) unchanged; only parameters with defaults were added (`OrderApi.placeOrder(idempotencyKey:)`).

## 6. Looking ahead

- What would you do with one more week?
  - Feature 3 (live tracking) on `watchOrderDocument` + foreground push.
  - Before sending a new idempotency key after a lost response, check `GET /v1/orders` for a matching recent order (closes the known gap in §2).
  - Widget/golden tests for the cart review card and a few integration tests driving Dev tools scenarios end to end.
  - A connectivity listener that reconciles when the device comes back online while the cart is open.
- What breaks first at 10× users (10k DAU)? What would you change?
  - Reconciling on every cart open doubles backend reads for the hottest path: cache the batch result for a few seconds and reconcile only when the cart changed or N seconds passed.
  - Catalog listing without HTTP caching: add ETags / `Cache-Control` on the real backend instead of the in-app cache that caused BUG-2.
  - Remote-config fan-out: every publish makes every open app refetch at once; add jitter to the refetch.
  - Idempotency keys should expire server-side (e.g. 24 h).
- How would you ship a hotfix for a critical bug without a store release?
  - Immediately: remote config – kill switch (`store_open`) or hide the broken section via `home_sections`; for wrong prices/fees, the server is the source of truth and the checkout already re-validates.
  - Force users off a bad build with `min_supported_version` once the fixed build is live in the stores.
  - For code-level fixes: staged rollout + feature flags read from remote config around risky paths (that is what this architecture enables); Shorebird-style code push only if the business accepts the store-policy trade-offs.
