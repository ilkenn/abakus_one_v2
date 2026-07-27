import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/core/services/remote_config/firebase_remote_config_service.dart';
import 'package:abakus_one_v2/core/services/remote_config/noop_remote_config_service.dart';
import 'package:abakus_one_v2/core/services/remote_config/remote_config_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remoteConfigServiceProvider', () {
    test(
        'resolves to NoOpRemoteConfigService when Firebase is not ready (default)',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(remoteConfigServiceProvider),
        isA<NoOpRemoteConfigService>(),
      );
    });

    test('resolves to FirebaseRemoteConfigService when Firebase is ready', () {
      final container = ProviderContainer(
        overrides: [firebaseReadyProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(remoteConfigServiceProvider),
        isA<FirebaseRemoteConfigService>(),
      );
    });
  });
}
