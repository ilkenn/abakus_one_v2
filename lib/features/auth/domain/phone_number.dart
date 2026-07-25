/// Turkish mobile phone number validation/normalization — a small, pure,
/// independently testable function per the explicit instruction not to
/// build a new feature/service just for this. The UI shows the number in a
/// human-friendly form (a fixed "+90" prefix next to a 10-digit field);
/// everything below the UI (repository, domain, secure storage) only ever
/// sees the normalized `+905XXXXXXXXX` form — visual separators never cross
/// that boundary.
abstract final class TurkishPhoneNumber {
  TurkishPhoneNumber._();

  /// Accepts the raw local part the user typed (the leading `+90` is fixed
  /// UI chrome, never entered by the user) and returns the normalized
  /// `+905XXXXXXXXX` form, or `null` if it isn't a valid Turkish mobile
  /// number.
  static String? normalize(String rawLocalInput) {
    final digitsOnly = rawLocalInput.replaceAll(RegExp(r'[^0-9]'), '');
    if (!isValidLocalNumber(digitsOnly)) {
      return null;
    }
    return '+90$digitsOnly';
  }

  /// Whether [digitsOnly] is a valid Turkish mobile local number: exactly
  /// 10 digits, starting with `5`.
  static bool isValidLocalNumber(String digitsOnly) {
    return RegExp(r'^5\d{9}$').hasMatch(digitsOnly);
  }
}
