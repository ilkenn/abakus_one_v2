import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/core/services/app_check/app_check_provider.dart';
import 'package:abakus_one_v2/core/services/app_check/firebase_app_check_service.dart';
import 'package:abakus_one_v2/core/services/app_check/noop_app_check_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appCheckServiceProvider', () {
    test('resolves to NoOpAppCheckService when Firebase is not ready (default)',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(appCheckServiceProvider),
        isA<NoOpAppCheckService>(),
      );
    });

    test('resolves to FirebaseAppCheckService when Firebase is ready', () {
      final container = ProviderContainer(
        overrides: [firebaseReadyProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appCheckServiceProvider),
        isA<FirebaseAppCheckService>(),
      );
    });
  });
}
