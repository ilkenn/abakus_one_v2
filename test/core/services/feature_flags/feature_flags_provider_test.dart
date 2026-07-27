import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_keys.dart';
import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_provider.dart';
import 'package:abakus_one_v2/core/services/feature_flags/remote_config_feature_flags_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('featureFlagsServiceProvider', () {
    test('resolves to a RemoteConfigFeatureFlagsService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(featureFlagsServiceProvider);

      expect(service, isA<RemoteConfigFeatureFlagsService>());
    });

    test('default (NoOp-backed) resolution is deterministic and fail-safe', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(featureFlagsServiceProvider);

      expect(service.isEnabled(FeatureFlagsKeys.bowlBuilderEnabled), isFalse);
      expect(
        service.isEnabled(
          FeatureFlagsKeys.bowlBuilderEnabled,
          defaultValue: true,
        ),
        isTrue,
      );
    });
  });
}
