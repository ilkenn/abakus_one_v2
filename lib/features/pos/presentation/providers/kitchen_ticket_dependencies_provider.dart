import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/kitchen_ticket_id_generator.dart';
import '../../data/kitchen_ticket_repository.dart';
import '../../domain/kitchen/kitchen_ticket_print_provider.dart';

/// The [KitchenTicketRepository] currently in use.
/// [InMemoryKitchenTicketRepository] today — no backend persistence
/// exists yet. Mirrors `paymentSessionRepositoryProvider`'s existing
/// shape.
final kitchenTicketRepositoryProvider =
    Provider<KitchenTicketRepository>((ref) {
  return InMemoryKitchenTicketRepository();
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
