import 'package:flutter/foundation.dart';

import 'log_level.dart';
import 'log_redactor.dart';
import 'logging_service.dart';

/// The **development logging** implementation of [LoggingService]: formats
/// each entry into a single readable line — sanitizing [message] and
/// [context] before any of it reaches [debugPrint] — and writes it. This
/// is what a locally-run debug/profile build uses; see
/// `logging_provider.dart` for how it's selected.
///
/// Every piece of output is sanitized: [context] via
/// [LogRedactor.redactContext] (by key name), [message] and `error`'s
/// `toString()` via [LogRedactor.sanitizeText] (by pattern) — the only
/// unsanitized part of a printed entry is [stackTrace], which is code
/// locations, not user data.
///
/// Wrapped in its own `try`/`catch` so a logging call can never crash the
/// app it's trying to help debug, even if formatting or the underlying
/// [debugPrint] call itself fails.
final class ConsoleLoggingService implements LoggingService {
  const ConsoleLoggingService();

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    try {
      final buffer = StringBuffer(
        '[${level.name.toUpperCase()}] ${LogRedactor.sanitizeText(message)}',
      );
      if (context != null && context.isNotEmpty) {
        buffer.write(' | context: ${LogRedactor.redactContext(context)}');
      }
      if (error != null) {
        buffer.write(
          ' | error: ${LogRedactor.sanitizeText(error.toString())}',
        );
      }
      if (stackTrace != null) {
        buffer.write('\n$stackTrace');
      }
      debugPrint(buffer.toString());
    } catch (_) {
      // Logging must never crash the app it's trying to help debug.
    }
  }
}
