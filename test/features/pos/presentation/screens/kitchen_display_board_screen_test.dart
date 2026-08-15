import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kitchen_ticket_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/kitchen_display_board_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/kds_test_fixtures.dart';

/// Faz R.3C.2 — simulates what `FirestoreKitchenTicketRepository` actually
/// does when `firestore.rules`' `hasBranchAccess` denies the caller: the
/// stream/future errors with a `permission-denied` `FirebaseException`,
/// never an empty result. Never a real Firestore SDK involved.
class _PermissionDeniedKitchenTicketRepository
    implements KitchenTicketRepository {
  @override
  Future<void> save(KitchenTicket ticket) async {}

  @override
  Future<KitchenTicket?> findById(String ticketId) async => null;

  @override
  Future<List<KitchenTicket>> findByOrderId(OrderId orderId) async => const [];

  @override
  Future<List<KitchenTicket>> findActiveByBranch(String branchId) {
    throw fs.FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied');
  }

  @override
  Stream<List<KitchenTicket>> watchActiveByBranch(String branchId) {
    return Stream.error(
      fs.FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied'),
    );
  }
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required KitchenTicketRepository ticketRepository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kitchenTicketRepositoryProvider.overrideWithValue(ticketRepository),
          kitchenProjectionRepositoryProvider
              .overrideWithValue(InMemoryKitchenProjectionRepository()),
        ],
        child: const MaterialApp(
          home: KitchenDisplayBoardScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty branch shows the empty-state view', (tester) async {
    await pumpScreen(tester,
        ticketRepository: InMemoryKitchenTicketRepository());

    expect(find.text('Bekleyen sipariş yok'), findsOneWidget);
  });

  testWidgets(
      'auto-enqueues work items for a fired ticket and shows its '
      'line', (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());

    await pumpScreen(tester, ticketRepository: ticketRepository);

    expect(find.text('ORD-1'), findsOneWidget);
    expect(find.textContaining('Ürün 0'), findsOneWidget);
  });

  testWidgets('the station filter chips are present and selectable',
      (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());
    await pumpScreen(tester, ticketRepository: ticketRepository);

    expect(find.widgetWithText(ChoiceChip, 'Tümü'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Sıcak'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Sıcak'));
    await tester.pumpAndSettle();

    // No rule routes anything to hot, so the shared-station ticket
    // disappears from a hot-only filtered view.
    expect(find.text('Bekleyen sipariş yok'), findsOneWidget);
  });

  // Faz R.3C — a ticket appearing on the branch's active set AFTER the
  // screen is already showing must appear with no manual reload/restart,
  // proving the board is subscribed to `watchActiveByBranch`, not just a
  // one-shot `findActiveByBranch` read at load time (this is exactly what
  // the reservation-preorder KDS release scheduler relies on in
  // production: an order flipping from `pendingConfirmation` to
  // `confirmed` must surface here with nobody pulling to refresh).
  testWidgets(
      'a ticket that becomes active after the screen is already showing appears with no manual reload',
      (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await pumpScreen(tester, ticketRepository: ticketRepository);

    expect(find.text('Bekleyen sipariş yok'), findsOneWidget);
    expect(find.text('ORD-1'), findsNothing);

    await ticketRepository.save(buildTestKitchenTicket());
    await tester.pumpAndSettle();

    expect(find.text('ORD-1'), findsOneWidget);
  });

  // Faz R.3C.2 — the real authorization boundary is
  // `firestore.rules`' `hasBranchAccess`, not this screen's own `branchId`
  // filter; a staff member without access to this branch must see a safe,
  // explicit access-denied state, never an infinite loading spinner or an
  // unhandled exception.
  testWidgets(
      'a permission-denied error (staff lacks branch access) shows a safe access-denied state, not an infinite loader or a crash',
      (tester) async {
    await pumpScreen(
      tester,
      ticketRepository: _PermissionDeniedKitchenTicketRepository(),
    );

    expect(find.text('Bu şube için mutfak ekranı erişim yetkiniz yok.'),
        findsOneWidget);
    expect(find.text('Mutfak ekranı yükleniyor...'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
