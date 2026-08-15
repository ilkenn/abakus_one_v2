import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../application/identity/kitchen_ticket_id_generator.dart';
import '../../data/firestore_kitchen_ticket_repository.dart';
import '../../data/kitchen_ticket_repository.dart';
import '../../domain/kitchen/kitchen_ticket_print_provider.dart';

/// The [KitchenTicketRepository] currently in use.
///
/// **Faz R.3C**: gated on [firebaseReadyProvider], mirroring
/// `canonicalOrderRepositoryProvider`/`deviceTokenRepositoryProvider`'s own
/// real/in-memory split — this previously resolved to
/// [InMemoryKitchenTicketRepository] unconditionally, including in release
/// builds, which is exactly the disclosed gap this phase closes: once
/// Firebase is ready, the KDS board reads live from the canonical `orders`
/// collection via [FirestoreKitchenTicketRepository]; [InMemory*] remains
/// the fallback for `flutter test` and any environment where Firebase
/// hasn't finished bootstrapping.
final kitchenTicketRepositoryProvider =
    Provider<KitchenTicketRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return InMemoryKitchenTicketRepository();
  }
  return FirestoreKitchenTicketRepository();
});

final kitchenTicketIdGeneratorProvider =
    Provider<KitchenTicketIdGenerator>((ref) {
  return SequentialKitchenTicketIdGenerator();
});

/// The production default is the honest "unavailable" `NoOp` — no real
/// kitchen printer integration exists this sprint (mirrors
/// `receiptPrintProviderProvider`'s existing shape).
final kitchenTicketPrintProviderProvider =
    Provider<KitchenTicketPrintProvider>((ref) {
  return const NoOpKitchenTicketPrintProvider();
});
