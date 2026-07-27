import 'package:abakus_one_v2/core/services/feature_flags/noop_feature_flags_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoOpFeatureFlagsService', () {
    test('isInitialized is false before initialize is called', () {
      final service = NoOpFeatureFlagsService();
      expect(service.isInitialized, isFalse);
    });

    test('initialize completes without throwing and sets isInitialized',
        () async {
      final service = NoOpFeatureFlagsService();
      await expectLater(service.initialize(), completes);
      expect(service.isInitialized, isTrue);
    });

    test('isEnabled returns the given defaultValue', () {
      final service = NoOpFeatureFlagsService();
      expect(service.isEnabled('any_flag'), isFalse);
      expect(
        service.isEnabled('any_flag', defaultValue: true),
        isTrue,
      );
    });

    test('getString returns the given defaultValue', () {
      final service = NoOpFeatureFlagsService();
      expect(service.getString('any_flag'), '');
      expect(
        service.getString('any_flag', defaultValue: 'fallback'),
        'fallback',
      );
    });

    test('getInt returns the given defaultValue', () {
      final service = NoOpFeatureFlagsService();
      expect(service.getInt('any_flag'), 0);
      expect(service.getInt('any_flag', defaultValue: 7), 7);
    });
  });
}
