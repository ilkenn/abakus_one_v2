import 'package:flutter/foundation.dart';

abstract interface class CrashReportingService {
  /// Activates crash collection for the current environment. Never
  /// throws — any failure is caught, logged, and left as "not activated,"
  /// mirroring `AppCheckService.initialize`'s exact contract, so app
  /// startup is never blocked by crash-reporting setup.
  Future<void> initialize();

  Future<void> recordError(
    Object error, {
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
    Map<String, Object?>? context,
  });

  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    bool fatal = false,
  });

  Future<void> log(String message);

  Future<void> setUserIdentifier(String identifier);

  Future<void> setCustomKey(String key, Object value);
}
