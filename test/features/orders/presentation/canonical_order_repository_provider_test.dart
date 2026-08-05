import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonicalOrderRepositoryProvider', () {
    test(
        'resolves to InMemoryCanonicalOrderRepository when Firebase is not '
        'ready (default) — including every `flutter test` run', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(canonicalOrderRepositoryProvider),
        isA<InMemoryCanonicalOrderRepository>(),
      );
    });

    test(
        'resolves to FirestoreCanonicalOrderRepository when Firebase is '
        'ready — no release build may silently persist orders in memory '
        'only', () {
      final container = ProviderContainer(
        overrides: [firebaseReadyProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(canonicalOrderRepositoryProvider),
        isA<FirestoreCanonicalOrderRepository>(),
      );
    });
  });
}
