import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/firebase_ready_provider.dart';
import '../../config/app_environment_config_provider.dart';
import '../logging/logging_provider.dart';
import 'crash_reporting_service.dart';
import 'firebase_crashlytics_service.dart';
import 'noop_crash_reporting_service.dart';

/// The application-wide [CrashReportingService] — Phase 9
/// (`docs/decisions.md` ADR-026). Resolves to [FirebaseCrashlyticsService]
/// once Firebase has actually initialized successfully
/// ([firebaseReadyProvider]); falls back to [NoOpCrashReportingService]
/// otherwise — including every `flutter test` run, where no real Firebase
/// app exists — mirrors `appCheckServiceProvider`'s exact shape.
final crashReportingServiceProvider = Provider<CrashReportingService>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const NoOpCrashReportingService();
  }
  return FirebaseCrashlyticsService(
    allowsDebugTooling:
        ref.watch(appEnvironmentConfigProvider).allowsDebugTooling,
    loggingService: ref.watch(loggingServiceProvider),
  );
});
