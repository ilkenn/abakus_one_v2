import 'package:flutter/foundation.dart';

import 'log_level.dart';
import 'log_redactor.dart';
import 'logging_service.dart';

/// The **development logging** implementation of [LoggingService]: formats
/// each entry into a single readable line (redacting [context] first) and
/// writes it via [debugPrint]. This is what a locally-run debug/profile
/// build uses; see `logging_provider.dart` for how it's selected.
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
      final buffer = StringBuffer('[${level.name.toUpperCase()}] $message');
      if (context != null && context.isNotEmpty) {
        buffer.write(' | context: ${LogRedactor.redactContext(context)}');
      }
      if (error != null) {
        buffer.write(' | error: $error');
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
