import 'package:abakus_one_v2/core/services/feature_flags/noop_feature_flags_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoOpFeatureFlagsService', () {
    test('initialize completes without throwing', () async {
      const service = NoOpFeatureFlagsService();
      await expectLater(service.initialize(), completes);
    });

    test('isEnabled returns the given defaultValue', () {
      const service = NoOpFeatureFlagsService();
      expect(service.isEnabled('any_flag'), isFalse);
      expect(
        service.isEnabled('any_flag', defaultValue: true),
        isTrue,
      );
    });
  });
}
