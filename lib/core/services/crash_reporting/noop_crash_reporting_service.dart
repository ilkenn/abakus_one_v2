import 'package:flutter/foundation.dart';
import 'crash_reporting_service.dart';

class NoOpCrashReportingService implements CrashReportingService {
  const NoOpCrashReportingService();

  @override
  Future<void> recordError(
    Object error, {
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
    Map<String, Object?>? context,
  }) async {}

  @override
  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    bool fatal = false,
  }) async {}

  @override
  Future<void> log(String message) async {}

  @override
  Future<void> setUserIdentifier(String identifier) async {}

  @override
  Future<void> setCustomKey(String key, Object value) async {}
}
