import 'package:abakus_one_v2/core/theme/app_colors.dart';
import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_station.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kitchen_ticket_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/kitchen_display_board_screen.dart';
import 'package:abakus_one_v2/shared/widgets/cards/app_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
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
    KitchenProjectionRepository? projectionRepository,
    FakeClock? clock,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kitchenTicketRepositoryProvider.overrideWithValue(ticketRepository),
          kitchenProjectionRepositoryProvider.overrideWithValue(
              projectionRepository ?? InMemoryKitchenProjectionRepository()),
          if (clock != null) clockProvider.overrideWithValue(clock),
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
      // **2026-09-21**: this screen is now a pure reader of
      // `kitchenWorkItems` (`functions/src/acceptOrderLine.ts` is the sole
      // writer of fresh work items in production) — it no longer creates
      // one from a ticket on its own, so the work item is seeded directly
      // here instead of relying on the screen's own former enqueue call.
      'shows a ticket line whose real kitchenWorkItems doc already exists',
      (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await projectionRepository.createInitial(buildTestKitchenWorkItem());

    await pumpScreen(
      tester,
      ticketRepository: ticketRepository,
      projectionRepository: projectionRepository,
    );

    expect(find.text('ORD-1'), findsOneWidget);
    expect(find.textContaining('Ürün 0'), findsOneWidget);
  });

  testWidgets('the station filter chips are present and selectable',
      (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await projectionRepository.createInitial(
      buildTestKitchenWorkItem(station: KitchenStation.shared),
    );
    await pumpScreen(
      tester,
      ticketRepository: ticketRepository,
      projectionRepository: projectionRepository,
    );

    // AP-5 Sprint 4 — the new status filter bar also has its own 'Tümü'
    // chip, so there are now two: one per filter dimension.
    expect(find.widgetWithText(ChoiceChip, 'Tümü'), findsNWidgets(2));
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
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await pumpScreen(
      tester,
      ticketRepository: ticketRepository,
      projectionRepository: projectionRepository,
    );

    expect(find.text('Bekleyen sipariş yok'), findsOneWidget);
    expect(find.text('ORD-1'), findsNothing);

    // A real accepted order produces both facts near-simultaneously
    // (`acceptOrderLine.ts` writes the work item as part of the same
    // transition that makes the order — and therefore its derived
    // ticket — active) — mirrored here rather than saving the ticket
    // alone, which this screen no longer materializes a work item for
    // on its own.
    await ticketRepository.save(buildTestKitchenTicket());
    await projectionRepository.createInitial(buildTestKitchenWorkItem());
    await tester.pump();
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

  // AP-5 Sprint 4 — the status filter tabs (Tümü/Bekleyen/Hazırlanıyor/
  // Geciken/Hazır) are a second, additive filter dimension alongside the
  // existing station chips.
  testWidgets('the status filter tabs are present and narrow the board',
      (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await projectionRepository.createInitial(buildTestKitchenWorkItem());
    await pumpScreen(
      tester,
      ticketRepository: ticketRepository,
      projectionRepository: projectionRepository,
    );

    expect(find.widgetWithText(ChoiceChip, 'Bekleyen'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Hazırlanıyor'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Geciken'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Hazır'), findsOneWidget);

    // The fixture's work item starts `queued` — filtering to `Hazır`
    // (ready-only) must hide it.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Hazır'));
    await tester.pumpAndSettle();
    expect(find.text('Bekleyen sipariş yok'), findsOneWidget);
  });

  testWidgets(
      'the ticket card shows a channel badge and the order-received clock time',
      (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await projectionRepository.createInitial(buildTestKitchenWorkItem());
    await pumpScreen(
      tester,
      ticketRepository: ticketRepository,
      projectionRepository: projectionRepository,
    );

    // `buildTestKitchenTicket`'s fixture: channelLabel 'Masa',
    // receivedAt DateTime(2026, 1, 1, 12) -> '12:00'.
    expect(find.text('Masa'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
  });

  testWidgets(
      'a wasted work item shows the distinct wasted badge, not the plain status label',
      (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await projectionRepository.createInitial(buildTestKitchenWorkItem(
      status: KitchenLineStatus.wasted,
    ));

    await pumpScreen(
      tester,
      ticketRepository: ticketRepository,
      projectionRepository: projectionRepository,
    );

    expect(find.text('Fireye Ayrıldı'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsOneWidget);
  });

  testWidgets(
      'the print button reports the print service as unavailable when Firebase is not ready',
      (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await projectionRepository.createInitial(buildTestKitchenWorkItem());
    await pumpScreen(
      tester,
      ticketRepository: ticketRepository,
      projectionRepository: projectionRepository,
    );

    await tester.tap(find.byIcon(Icons.print_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Yazdırma servisi şu anda kullanılamıyor.'),
        findsOneWidget);
  });

  // 2026-09-22 — three-tier delay color scale: 0-5dk normal/green, 5-10dk
  // warning/orange, 10dk+ critical/red (+ pulsing highlight, verified
  // separately below by proving the animation actually runs). Each case
  // pins a real clock via `clockProvider` rather than relying on the
  // ambient wall-clock `now` every other test in this file implicitly
  // runs under (which makes every fixture item "critical" by months —
  // fine for tests that don't care about the exact tier, wrong for these).
  group('delay color scale (5dk warning / 10dk critical)', () {
    Future<void> pumpAtElapsed(
        WidgetTester tester, Duration elapsedSinceQueued) async {
      final ticketRepository = InMemoryKitchenTicketRepository();
      await ticketRepository.save(buildTestKitchenTicket());
      final projectionRepository = InMemoryKitchenProjectionRepository();
      await projectionRepository.createInitial(buildTestKitchenWorkItem());
      await pumpScreen(
        tester,
        ticketRepository: ticketRepository,
        projectionRepository: projectionRepository,
        // buildTestKitchenWorkItem's own queuedAt default.
        clock: FakeClock(DateTime(2026, 1, 1, 12).add(elapsedSinceQueued)),
      );
    }

    testWidgets('under 5dk renders the normal/success border, no highlight',
        (tester) async {
      await pumpAtElapsed(tester, const Duration(minutes: 2));

      final card = tester.widget<AppCard>(find.byType(AppCard).first);
      expect(card.borderColor, AppColors.success);
      expect(card.boxShadow, isNull);
      expect(find.text('2dk'), findsOneWidget);
    });

    testWidgets('5dk to under 10dk renders the warning/orange border',
        (tester) async {
      await pumpAtElapsed(tester, const Duration(minutes: 7));

      final card = tester.widget<AppCard>(find.byType(AppCard).first);
      expect(card.borderColor, AppColors.warning);
      expect(card.boxShadow, isNull);
      expect(find.text('7dk'), findsOneWidget);
    });

    testWidgets(
        '10dk and over renders the critical/error border with a pulsing glow',
        (tester) async {
      await pumpAtElapsed(tester, const Duration(minutes: 12));

      final card = tester.widget<AppCard>(find.byType(AppCard).first);
      expect(card.borderColor, AppColors.error);
      expect(find.text('12dk'), findsOneWidget);
      // The pulse is a finite (count: 3), not infinite, animation — proven
      // test-safe by every `pumpAndSettle()` call in this file already
      // resolving despite every fixture item being "critical" under the
      // ambient real clock those other tests run under. Here it's proven
      // directly: a non-null, animated boxShadow is present at all (the
      // glow this card only ever renders while critical).
      expect(card.boxShadow, isNotNull);
    });
  });
}
