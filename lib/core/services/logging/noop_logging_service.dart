import 'log_level.dart';
import 'logging_service.dart';

/// A [LoggingService] that discards every entry. Used wherever logging
/// should be silent (see `logging_provider.dart`).
final class NoOpLoggingService implements LoggingService {
  const NoOpLoggingService();

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {}
}
