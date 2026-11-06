# Bugs found & fixed

> One section per bug. Order doesn't matter. Keep each one short and precise.
> Commit the reproducing test **before** the fix.

---

## BUG-1: Removed / decremented cart items come back after restart (QK-101)

- **Symptom:** Remove chips and reduce milk 2 → 1, close and reopen the app: chips are back, milk is 2 again, the badge shows the old count. A removed coupon also comes back.
- **Steps to reproduce:**
  1. Add chips and 2 × eggs, apply `SAVE10`.
  2. Remove chips, tap − on eggs, remove the coupon.
  3. Fully restart the app → open the cart.
- **Root cause:** `CartController.decrement`, `remove` and `removeCoupon` (`lib/features/cart/application/cart_controller.dart`) only set `state`; unlike `add`/`increment` they never called `CartStorage.save`. `main.dart` restores the last *saved* cart.
- **Fix:** Every mutation persists the new cart. (Later refactored into a single `_commit`, see BUG-15.)
- **Test:** `test/bugs/qk101_cart_persistence_test.dart` → `remove, decrement and removeCoupon survive an app restart`
- **Commits:** test `299448c` → fix `b9c187c`

---

## BUG-2: Prices and "My orders" don't update until restart (QK-102)

- **Symptom:** A price changed on the server, but pull-to-refresh still shows the old one; a just-placed order is missing from *My orders*. Everything is correct after killing the app.
- **Steps to reproduce:**
  1. Open Home, then Dev tools → *Change a random product price now*.
  2. Back on Home, pull to refresh: old price.
  3. Open *My orders*, go back, place an order, open *My orders* again: the new order is missing.
- **Root cause:** `ApiClient._getWithRetry` (`lib/core/network/api_client.dart`) answered every GET from a 10-minute in-memory cache *before* trying the network, so refresh, orders and `/v1/config` were frozen for 10 minutes (the cache dies with the process, hence "works after restart"). Separately, `ordersProvider` (`lib/features/orders/data/order_tracking_repository.dart`) was a non-autoDispose `FutureProvider` that kept its first result for the whole session.
- **Fix:** Removed the response cache (offline browsing is `CatalogCache`'s job, network-first); `ordersProvider` is `autoDispose`, so it refetches every time *My orders* opens.
- **Test:** `test/bugs/qk102_stale_data_test.dart` → `pull-to-refresh shows a price that changed on the server`, `My orders shows an order placed after it was first opened`
- **Commits:** test `cf65004` → fix `379b1a8`

---

## BUG-3: ₹19.99 is parsed as 1998 paise, so orders always fail

- **Symptom:** Any cart containing e.g. Hybrid Tomato (₹19.99), Green Grapes (₹79.99) or Roasted Peanuts (₹69.99) can never be ordered: the server answers `PRICE_CHANGED` every time.
- **Steps to reproduce:**
  1. Add Hybrid Tomato to the cart.
  2. Place order → error, every time.
- **Root cause:** `rupeesToPaise` (`lib/core/utils/money.dart`) did `(rupees * 100).toInt()`. `19.99 * 100` is `1998.9999…` in floating point and `toInt()` truncates to 1998, while the server's price is 1999.
- **Fix:** `.round()` instead of `.toInt()`: the API gives at most 2 decimals, so rounding to the nearest paisa is exact.
- **Test:** `test/bugs/money_rupees_to_paise_test.dart` → `rupeesToPaise is exact for prices with paise`, `a ₹19.99 tomato from the catalog can be ordered`
- **Commits:** test `4075da0` → fix `e8f3703`

---

## BUG-4: Prices are shown without paise (₹19.99 → "₹19")

- **Symptom:** Product cards, the cart and the bill show ₹19 for a ₹19.99 product; the "To pay" amount is lower than what is charged.
- **Steps to reproduce:**
  1. Open Fruits & Veggies → Hybrid Tomato shows "₹19".
- **Root cause:** `formatMoney` (`lib/core/utils/money.dart`) printed only `paise ~/ 100`. BUSINESS_RULES §1: "₹50, ₹49.99" – paise shown when there are any.
- **Fix:** Print `₹rupees` when paise are 0, otherwise `₹rupees.pp` (2 digits); negative amounts get a leading `-`.
- **Test:** `test/bugs/money_format_test.dart` → `formatMoney shows paise only when there are any`
- **Commits:** test `1c5d872` → fix `40179b8`

---

## BUG-5: Legacy products crash the catalog (Dairy spins forever, "milk" search breaks)

- **Symptom:** The Dairy category never stops loading; the second page of *All products* never loads; searching "milk" fails.
- **Steps to reproduce:**
  1. Tap the *Dairy, Bread & Eggs* category → endless spinner.
  2. Or search "milk".
- **Root cause:** Products still served by the legacy catalog (`dairy-00`, `dairy-02`, `snacks-09`) send `"mrp": null` and `"stock": "120"` (a string). `ProductDto.fromJson` (`lib/features/catalog/data/product_dto.dart`) cast with `as num` / `as int` → `TypeError`. Controllers only catch `ApiException`, so the error escaped and the loading flag was never cleared.
- **Fix:** Parse numbers leniently (num or numeric string) and treat a missing MRP as "no discount" (MRP = price). Fixing the boundary is better than catching everything in each controller.
- **Test:** `test/bugs/legacy_product_parsing_test.dart` → `the Dairy page (with legacy products) loads`, `the Dairy screen leaves the loading state`, `searching "milk" works`
- **Commits:** test `8984841` → fix `d287d56`

---

## BUG-6: Delivery fee charged at exactly ₹199

- **Symptom:** A cart of exactly ₹199 shows a ₹25 delivery fee and the order fails with `TOTAL_MISMATCH`.
- **Steps to reproduce:**
  1. Build a cart worth exactly ₹199 (e.g. 1 × Alphonso Mango).
  2. The bill shows a ₹25 delivery fee; place order → error.
- **Root cause:** `CartPricing.compute` (`lib/features/cart/domain/cart_pricing.dart`) used `payable > threshold`; BUSINESS_RULES §2 says "₹199 **or more**" (the server uses `>=`).
- **Fix:** `>=`.
- **Test:** `test/bugs/free_delivery_threshold_test.dart` → `exactly ₹199 gets free delivery`
- **Commits:** test `1011c1f` → fix `76a9ffd`

---

## BUG-7: Lost response / timeout creates a second order (customers charged twice)

- **Symptom:** On a slow network the customer ends up with two identical orders.
- **Steps to reproduce:**
  1. Add something to the cart, Dev tools → *Lose next*.
  2. Place order: success, but Dev tools → Orders shows **two** orders.
- **Root cause:** `CheckoutController._placeOrder` (`lib/features/checkout/application/checkout_controller.dart`) retried on `ApiTimeoutException` with a brand-new request and `OrderApi.placeOrder` never sent an `Idempotency-Key`. A timeout does not mean the server didn't create the order.
- **Fix:** Every order carries an `Idempotency-Key` (UUID v4). The key is stored on the device with a fingerprint of the exact request body and reused for the same cart, also on a second tap and after an app restart; it is dropped after success or a definite 4xx. The final timeout message now says the order *may* have been placed.
- **Test:** `test/bugs/checkout_lost_response_test.dart` → `lost response + automatic retry creates exactly one order`, `tapping "Place order" again after a timeout creates no second order`, `...also after an app restart`
- **Commits:** test `c6873f9` → fix `026ce26`

---

## BUG-8: Double tap on "Place order" creates two orders

- **Symptom:** Two quick taps → two orders.
- **Steps to reproduce:**
  1. Dev tools → Latency *Slow 3G*.
  2. Tap *Place order* twice quickly.
- **Root cause:** The button (`lib/features/cart/presentation/cart_screen.dart`) stayed enabled while placing, and `placeOrder` had no in-flight guard; both calls generated their own key.
- **Fix:** `placeOrder` returns the in-flight `Future` to a second caller; the button is disabled while placing.
- **Test:** `test/bugs/checkout_double_tap_test.dart` → `two placeOrder calls at the same time create one order`
- **Commits:** test `afbfab8` → fix `a987f51`

---

## BUG-9: Order rejected when the coupon minimum is not met

- **Symptom:** With SAVE10 applied to a ₹49 cart, the cart correctly shows "Add ₹150 more to use this coupon", but placing the order fails with "Coupon cannot be applied".
- **Steps to reproduce:**
  1. Add a banana (₹49), apply `SAVE10`.
  2. Place order → error.
- **Root cause:** BUSINESS_RULES §3: below the minimum "the coupon stays applied but gives no discount … the customer can still place the order". The server rejects a code below its minimum (`COUPON_INVALID / MIN_ORDER_NOT_MET`), and `OrderApi` always sent `couponCode`.
- **Fix:** `OrderApi.buildBody` sends the code only when `subtotal >= minOrderPaise`; the coupon stays in the cart, so it kicks in once the user adds more.
- **Test:** `test/bugs/coupon_below_minimum_test.dart` → `an order below the coupon minimum can still be placed`
- **Commits:** test `3f67ada` → fix `c1fc076`

---

## BUG-10: Offline, a category shows another category's products

- **Symptom:** Offline, opening *Beverages* shows fruits (whatever list was loaded last).
- **Steps to reproduce:**
  1. Open Beverages, go back to Home.
  2. Dev tools → Offline, open Beverages again.
- **Root cause:** `CatalogRepository.getPage` (`lib/features/catalog/data/catalog_repository.dart`) used the cache key `page.<cursor>`, without the category: every category's first page overwrote the same entry.
- **Fix:** Key is `page.<categoryId>.<cursor>`.
- **Test:** `test/bugs/catalog_offline_cache_test.dart` → `offline category page comes from that category's cache`
- **Commits:** test `f190e7c` → fix `4f74790`

---

## BUG-11: Scrolling duplicates products in the grid

- **Symptom:** While scrolling, the same products appear two or three times.
- **Steps to reproduce:**
  1. Open a category with more than one page (e.g. Fruits), scroll down quickly.
- **Root cause:** The scroll listener calls `CatalogController.loadMore` (`lib/features/catalog/presentation/catalog_controller.dart`) on every scroll event and `loadMore` didn't check `isLoadingMore`, so the same cursor was fetched and appended several times. A `loadMore` finishing after a refresh could also append a stale page.
- **Fix:** `loadMore` returns early while a load/refresh is running or before the first page; a generation counter drops results that started before a refresh.
- **Test:** `test/bugs/catalog_load_more_test.dart` → `concurrent loadMore calls do not duplicate products`
- **Commits:** test `31a5ed8` → fix `c9f4f88`

---

## BUG-12: CategoryScreen leaks a config listener and calls setState after dispose

- **Symptom:** Each visit to a category leaks a listener; publishing config after leaving the screen throws `setState() called after dispose()`. The free-delivery strip could also disagree with the fee in the cart.
- **Steps to reproduce:**
  1. Open a category, go back.
  2. Dev tools → *Free delivery ≥ ₹99* → error in the console.
- **Root cause:** `_CategoryScreenState.initState` (`lib/features/catalog/presentation/category_screen.dart`) subscribed to `remoteUpdates` and never cancelled, and kept a private copy of the threshold.
- **Fix:** Subscription cancelled in `dispose` and the screen reads the app-wide config. With Feature 2 (`c4f3311`) the controller follows live updates itself, so the screen now only watches it.
- **Test:** `test/bugs/category_screen_listener_test.dart` → `leaving the category screen removes its config listener`
- **Commits:** test `f4bba05` → fix `9c265fc`

---

## BUG-13: Search shows results for an older query

- **Symptom:** Type "banana" quickly; the list sometimes shows the results for "ba".
- **Steps to reproduce:**
  1. Dev tools → *Slow 3G*.
  2. Search, type quickly.
- **Root cause:** `ProductSearchController.search` (`lib/features/search/search_controller.dart`) sends one request per keystroke and whichever response arrives last wins.
- **Fix:** Each search gets an id; only the latest one may update the state.
- **Test:** `test/bugs/search_race_test.dart` → `a slow older search does not overwrite the newer one`
- **Commits:** test `c079ab9` → fix `4e63d6d`

---

## BUG-14: Permanent 4xx errors are retried

- **Symptom:** Errors such as "query too short" take ~0.6 s longer than needed; three identical requests hit the server.
- **Steps to reproduce:**
  1. Search a single letter: the error appears after a delay.
- **Root cause:** `ApiClient._getWithRetry` retried every `ApiException`, ignoring `isTransient`.
- **Fix:** Rethrow non-transient errors immediately; offline / timeout / 5xx are still retried.
- **Test:** `test/bugs/api_client_retry_test.dart` → `a 4xx GET is sent once, not retried` (plus `a 5xx GET is still retried`)
- **Commits:** test `8f429fa` → fix `7184f8e`

---

## BUG-15: Fast taps on "+" lose increments

- **Symptom:** Tapping + three times quickly adds only two.
- **Steps to reproduce:**
  1. Tap + rapidly on any product.
- **Root cause:** `add`/`increment` read `state`, awaited `_storage.save`, and only then wrote `state`: a second tap during the save started from the same old cart. Saves could also complete out of order.
- **Fix:** `state` is set synchronously and saves go through a FIFO queue, so storage always ends with the newest cart.
- **Test:** `test/bugs/cart_fast_tap_test.dart` → `two quick increments add two units, in memory and on disk`
- **Commits:** test `6b68ea6` → fix `113685e`

---

## Suspicious but NOT a bug

- `Coupon.discountFor` – flat capped at the cart value, percent rounded **down** with `~/`, capped by `maxDiscountPaise`: exactly BUSINESS_RULES §3.
- `Coupon.isExpired` treats "expires exactly now" as expired: matches the server (`!expiresAt.isAfter(now)`).
- `CatalogRepository.getPage` rethrows non-transient errors instead of serving the cache: a 4xx (e.g. bad cursor) is a real error, not "offline".
- `ServerException.isTransient` is false for 501 (Not Implemented will not start working on retry).
- `ApiClient.post` is never retried automatically: correct; retrying a POST is only safe with an idempotency key, which the checkout handles itself.
- `CartStorage.load` / `AppConfig.fromValues` silently fall back to empty/defaults on bad data: deliberate (a corrupt value must not crash the app).
- `Product.discountPercent` rounds down (e.g. 16.6 % → "16% OFF"): never over-promises a discount.
- `ProductCard` hides "ADD" for out-of-stock products but still shows the stepper if the item is already in the cart: lets the user remove it.
