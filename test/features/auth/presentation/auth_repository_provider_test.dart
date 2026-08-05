import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/production_unavailable_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('authRepositoryProvider', () {
    test(
        'resolves to ProductionUnavailableAuthRepository when Firebase is '
        'not ready (default) — never fakes a success', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(authRepositoryProvider),
        isA<ProductionUnavailableAuthRepository>(),
      );
    });

    test(
        'resolves to FirebaseAuthRepository when Firebase is ready — in '
        'every build mode, not just debug', () {
      final container = ProviderContainer(
        overrides: [firebaseReadyProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(authRepositoryProvider),
        isA<FirebaseAuthRepository>(),
      );
    });
  });
}
