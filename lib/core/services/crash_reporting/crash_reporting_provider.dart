import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'crash_reporting_service.dart';
import 'noop_crash_reporting_service.dart';

final crashReportingServiceProvider = Provider<CrashReportingService>((ref) {
  return const NoOpCrashReportingService();
});
