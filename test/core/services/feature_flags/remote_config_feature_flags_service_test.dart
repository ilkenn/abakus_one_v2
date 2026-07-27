import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_keys.dart';
import 'package:abakus_one_v2/core/services/feature_flags/remote_config_feature_flags_service.dart';
import 'package:abakus_one_v2/core/services/remote_config/noop_remote_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteConfigFeatureFlagsService', () {
    late RemoteConfigFeatureFlagsService service;

    setUp(() {
      service =
          RemoteConfigFeatureFlagsService(const NoOpRemoteConfigService());
    });

    test('isInitialized is false before initialize is called', () {
      expect(service.isInitialized, isFalse);
    });

    test(
        'initialize delegates to the underlying RemoteConfigService and sets isInitialized',
        () async {
      await expectLater(service.initialize(), completes);
      expect(service.isInitialized, isTrue);
    });

    group('isEnabled is deterministic and fail-safe for every known flag', () {
      const knownFlags = [
        FeatureFlagsKeys.otpLoginEnabled,
        FeatureFlagsKeys.bowlBuilderEnabled,
        FeatureFlagsKeys.fortuneWheelEnabled,
        FeatureFlagsKeys.reservationsEnabled,
        FeatureFlagsKeys.qrScannerEnabled,
      ];

      for (final flag in knownFlags) {
        test('"$flag" returns the given defaultValue (NoOp-backed)', () {
          expect(service.isEnabled(flag), isFalse);
          expect(service.isEnabled(flag, defaultValue: true), isTrue);
        });
      }
    });

    test(
        'an unrecognized flag name returns the given defaultValue for isEnabled/getString/getInt',
        () {
      expect(service.isEnabled('not_a_real_flag'), isFalse);
      expect(service.isEnabled('not_a_real_flag', defaultValue: true), isTrue);
      expect(service.getString('not_a_real_flag'), '');
      expect(
        service.getString('not_a_real_flag', defaultValue: 'fallback'),
        'fallback',
      );
      expect(service.getInt('not_a_real_flag'), 0);
      expect(service.getInt('not_a_real_flag', defaultValue: 7), 7);
    });

    test(
        'getString/getInt fall back to defaultValue for known flags (NoOp-backed)',
        () {
      expect(
        service.getString(
          FeatureFlagsKeys.bowlBuilderEnabled,
          defaultValue: 'fallback',
        ),
        'fallback',
      );
      expect(
        service.getInt(FeatureFlagsKeys.bowlBuilderEnabled, defaultValue: 7),
        7,
      );
    });

    test('repeated calls are deterministic', () {
      final first = service.isEnabled(FeatureFlagsKeys.otpLoginEnabled);
      final second = service.isEnabled(FeatureFlagsKeys.otpLoginEnabled);
      expect(first, second);
    });
  });
}
