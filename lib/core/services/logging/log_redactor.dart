/// The application's minimal log/report sanitization boundary.
///
/// Deliberately narrow: it redacts [Map] entries by *key name* only (a
/// structural check), not by scanning arbitrary free text for
/// sensitive-looking content. A general-purpose PII/secret scanner over
/// unstructured strings is its own hard problem (false positives/
/// negatives either way) and nothing in this codebase needs one yet —
/// see `logging_service.dart`'s doc comment for the convention this
/// implies for callers (sensitive values belong in a context map entry,
/// never interpolated into a log message).
abstract final class LogRedactor {
  LogRedactor._();

  static const String redactedValue = '[REDACTED]';

  /// Key-name substrings (matched case-insensitively) that mark a
  /// [redactContext] entry as sensitive.
  static const Set<String> _sensitiveKeyMarkers = {
    'token',
    'password',
    'secret',
    'otp',
    'pin',
    'cvv',
    'card',
    'phone',
    'email',
    'tc',
    'ssn',
  };

  /// Returns a copy of [context] with every value whose key matches a
  /// sensitive marker replaced by [redactedValue]. Keys themselves are
  /// never altered or removed — only values.
  static Map<String, Object?> redactContext(Map<String, Object?> context) {
    return context.map((key, value) {
      final isSensitive = _sensitiveKeyMarkers.any(
        key.toLowerCase().contains,
      );
      return MapEntry(key, isSensitive ? redactedValue : value);
    });
  }
}
