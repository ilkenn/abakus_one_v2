import 'package:abakus_one_v2/bootstrap/app_bootstrap.dart';
import 'package:abakus_one_v2/core/services/app_check/noop_app_check_service.dart';
import 'package:abakus_one_v2/core/services/crash_reporting/noop_crash_reporting_service.dart';
import 'package:abakus_one_v2/core/services/feature_flags/remote_config_feature_flags_service.dart';
import 'package:abakus_one_v2/core/services/remote_config/noop_remote_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// No real Firebase app exists under `flutter test`, so
/// [FirebaseBootstrapService.initialize] (called internally by
/// [bootstrapApp]) is expected to fail the same way
/// `firebase_bootstrap_service_test.dart`'s injected-failure cases do —
/// this proves the full, real orchestration sequence degrades safely
/// end-to-end, not just each service in isolation.
void main() {
  group('bootstrapApp', () {
    test('completes without throwing even with no real Firebase app available',
        () async {
      await expectLater(bootstrapApp(), completes);
    });

    test('reports Firebase as not ready and falls back to NoOp-backed services',
        () async {
      final result = await bootstrapApp();

      expect(result.isFirebaseReady, isFalse);
      expect(result.remoteConfigService, isA<NoOpRemoteConfigService>());
      expect(result.appCheckService, isA<NoOpAppCheckService>());
      expect(result.crashReportingService, isA<NoOpCrashReportingService>());
      expect(
          result.featureFlagsService, isA<RemoteConfigFeatureFlagsService>());
    });

    test('initializes the feature flags service before returning', () async {
      final result = await bootstrapApp();

      expect(result.featureFlagsService.isInitialized, isTrue);
    });

    test('providerOverrides contains one override per bootstrapped service',
        () async {
      final result = await bootstrapApp();

      expect(result.providerOverrides, hasLength(7));
    });

    test(
        'resolves auth state before returning — no persisted session in a '
        'test environment resolves to not signed in, not left unresolved',
        () async {
      final result = await bootstrapApp();

      expect(result.resolvedAuthState.isAuthenticated, isFalse);
      expect(result.resolvedAuthState.isGuest, isFalse);
    });
  });
}
