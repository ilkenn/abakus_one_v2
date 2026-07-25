import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_keys.dart';
import 'package:abakus_one_v2/core/services/feature_flags/remote_config_feature_flags_service.dart';
import 'package:abakus_one_v2/core/services/remote_config/noop_remote_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteConfigFeatureFlagsService', () {
    const service = RemoteConfigFeatureFlagsService(
      NoOpRemoteConfigService(),
    );

    test('initialize delegates to the underlying RemoteConfigService',
        () async {
      await expectLater(service.initialize(), completes);
    });

    group('isEnabled is deterministic and fail-safe for every known flag', () {
      const knownFlags = [
        FeatureFlagsKeys.loyalty,
        FeatureFlagsKeys.campaigns,
        FeatureFlagsKeys.reservations,
        FeatureFlagsKeys.delivery,
        FeatureFlagsKeys.qr,
        FeatureFlagsKeys.customBowl,
      ];

      for (final flag in knownFlags) {
        test('"$flag" returns the given defaultValue (NoOp-backed)', () {
          expect(service.isEnabled(flag), isFalse);
          expect(service.isEnabled(flag, defaultValue: true), isTrue);
        });
      }
    });

    test('an unrecognized flag name returns the given defaultValue', () {
      expect(service.isEnabled('not_a_real_flag'), isFalse);
      expect(
        service.isEnabled('not_a_real_flag', defaultValue: true),
        isTrue,
      );
    });

    test('repeated calls are deterministic', () {
      final first = service.isEnabled(FeatureFlagsKeys.loyalty);
      final second = service.isEnabled(FeatureFlagsKeys.loyalty);
      expect(first, second);
    });
  });
}
