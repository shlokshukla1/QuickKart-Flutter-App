/// Money helpers.
///
/// Every amount inside the app is an integer number of **paise**
/// (1 rupee = 100 paise). Never store money in a `double`.
library;

/// Formats paise for display.
///
/// FIX (money display): paise were dropped, so ₹19.99 showed as "₹19".
/// BUSINESS_RULES §1: show paise only when there are any (₹50, ₹49.99).
String formatMoney(int paise) {
  final rupees = paise ~/ 100;
  final rest = paise % 100;
  if (rest == 0) return '₹$rupees';
  return '₹$rupees.${rest.toString().padLeft(2, '0')}';
}

/// Converts a rupee amount coming from the (legacy) API into paise.
///
/// FIX (paise truncation): `19.99 * 100` is `1998.9999…` in floating point
/// and `.toInt()` cut it to 1998, so the app sent the wrong price and every
/// order failed with PRICE_CHANGED. Rounding gives the exact 1999.
int rupeesToPaise(num rupees) => (rupees * 100).round();
