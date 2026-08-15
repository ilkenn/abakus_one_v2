import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kitchen_ticket_dependencies_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Faz R.3C — `kitchenTicketRepositoryProvider` was previously ungated
  // (always `InMemoryKitchenTicketRepository`, including in release
  // builds). Now gated on `firebaseReadyProvider`, mirroring
  // `deviceTokenRepositoryProvider`/`canonicalOrderRepositoryProvider`.
  // The Firebase-ready branch (`FirestoreKitchenTicketRepository`) is not
  // exercised here for the same reason `device_token_providers_test.dart`
  // documents — its constructor eagerly touches `FirebaseFirestore
  // .instance`, unavailable in a plain `flutter test` process.
  test('resolves to InMemoryKitchenTicketRepository when Firebase is not ready',
      () {
    final container = ProviderContainer(
      overrides: [firebaseReadyProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(kitchenTicketRepositoryProvider),
      isA<InMemoryKitchenTicketRepository>(),
    );
  });

  test(
      'defaults to InMemoryKitchenTicketRepository with no override (test-safe default)',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(kitchenTicketRepositoryProvider),
      isA<InMemoryKitchenTicketRepository>(),
    );
  });
}
