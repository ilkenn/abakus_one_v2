import 'package:flutter/foundation.dart';

abstract interface class CrashReportingService {
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
