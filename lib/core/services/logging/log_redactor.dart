/// The application's minimal log/report sanitization boundary.
///
/// Two deliberately narrow mechanisms, not a general-purpose PII
/// classifier (that's its own hard problem — false positives/negatives
/// either way — and nothing in this codebase needs one):
/// - [redactContext] — structural: redacts a [Map] value by *key name*.
/// - [sanitizeText] — pattern-based: redacts a fixed, small set of
///   recognizable shapes (bearer/labeled tokens, emails, long digit runs
///   that look like phone/card numbers) out of free text. It matches
///   *shapes*, not meaning — favors over-redaction of a coincidentally
///   long number over under-redaction of a real one.
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

  /// `Bearer <token>` (case-insensitive; HTTP Authorization-header shape).
  static final RegExp _bearerTokenPattern = RegExp(
    r'\bBearer\s+\S+',
    caseSensitive: false,
  );

  /// `label: value` / `label=value` where `label` is one of the sensitive
  /// markers below — covers a token/password/OTP/PIN/CVV embedded in a
  /// free-text message with its usual key/value shape (e.g. an
  /// interpolated `'otp request failed for otp=$code'`).
  static final RegExp _labeledSecretPattern = RegExp(
    r'\b(access[_-]?token|refresh[_-]?token|api[_-]?key|token|secret|'
    r'password|pwd|otp|pin|cvv)\b\s*[:=]\s*\S+',
    caseSensitive: false,
  );

  /// A plausible email address.
  static final RegExp _emailPattern = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');

  /// A run of 10-19 digits, optionally with `+`/space/dash separators —
  /// covers both phone numbers (`+905321234567`, `5321234567`) and
  /// card-like numbers (`4111 1111 1111 1111`) without needing two
  /// separate patterns, since both are just "a long, mostly-digit run" to
  /// a shape-based matcher. Applied last, after the labeled-secret pass
  /// above has already consumed any digits that had an explicit label.
  static final RegExp _longDigitRunPattern = RegExp(r'\+?\d[\d\-\s]{8,18}\d');

  /// Redacts recognizable sensitive shapes out of free text — a log
  /// [LoggingService.log] `message` or an exception's `toString()`.
  /// Unlike [redactContext], there is no key to check here, so this
  /// matches by *pattern* against the whole string; see the class doc
  /// comment for what that trades away.
  static String sanitizeText(String text) {
    var sanitized = text.replaceAll(
      _bearerTokenPattern,
      'Bearer $redactedValue',
    );
    sanitized = sanitized.replaceAllMapped(
      _labeledSecretPattern,
      (match) => '${match.group(1)}: $redactedValue',
    );
    sanitized = sanitized.replaceAll(_emailPattern, redactedValue);
    sanitized = sanitized.replaceAll(_longDigitRunPattern, redactedValue);
    return sanitized;
  }
}
