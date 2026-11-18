import 'package:intl/intl.dart';

/// Centralized currency formatter strictly enforcing Section 15.3 of Standards:
/// 1. Amounts arrive as integers in paise (never floats).
/// 2. Single formatter produces all displayed amounts (no ad-hoc interpolation).
/// 3. Strict differentiation between Estimated and Final amounts.
class CurrencyFormatter {
  new _();

  static final NumberFormat _inrFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// Format integer paise into Indian Rupee currency string, e.g. 42650 -> "₹426.50"
  static String formatPaise(int paise) {
    final rupees = paise / 100.0;
    return _inrFormat.format(rupees);
  }

  /// Format with explicit prefix/suffix according to lifecycle status.
  static String formatWithStage(int paise, {required bool isFinal}) {
    final formatted = formatPaise(paise);
    return isFinal ? '$formatted (Final)' : '$formatted (Estimated)';
  }
}
