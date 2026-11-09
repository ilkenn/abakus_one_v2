import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kitchen_ticket_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/kitchen_order_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_pos_authorization_policy.dart';
import '../../test_support/kds_test_fixtures.dart';

void main() {
  Future<InMemoryKitchenProjectionRepository> pumpScreen(
    WidgetTester tester, {
    AuthorizationResult? authorization,
    String kitchenTicketIdToOpen = 'ticket-1',
    OrderChannel ticketChannel = OrderChannel.delivery,
    OrderStatus? orderStatus,
  }) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket(
        channel: ticketChannel, orderStatus: orderStatus));
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await projectionRepository.save(buildTestKitchenWorkItem());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kitchenTicketRepositoryProvider.overrideWithValue(ticketRepository),
          kitchenProjectionRepositoryProvider
              .overrideWithValue(projectionRepository),
          kitchenAuditEntryRepositoryProvider
              .overrideWithValue(InMemoryKitchenAuditEntryRepository()),
        ],
        child: MaterialApp(
          home: KitchenOrderDetailsScreen(
            kitchenTicketId: kitchenTicketIdToOpen,
            authorizationPolicy: authorization == null
                ? null
                : FakePosAuthorizationPolicy(authorization),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return projectionRepository;
  }

  testWidgets('shows the line and its current status', (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('Ürün 0'), findsOneWidget);
    expect(find.textContaining('queued'), findsOneWidget);
  });

  testWidgets('advancing the line calls TransitionKitchenWorkItem',
      (tester) async {
    final projectionRepository = await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    await tester.tap(find.widgetWithText(ElevatedButton, 'İlerlet'));
    await tester.pumpAndSettle();

    final item = await projectionRepository.findById('work-1');
    expect(item!.status, KitchenLineStatus.acknowledged);
  });

  testWidgets(
      'without an authorization policy, advancing surfaces a '
      'message', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'İlerlet'));
    await tester.pumpAndSettle();

    expect(find.text('Yetki politikası tanımlı değil.'), findsOneWidget);
  });

  testWidgets(
      '2026-10-29: a mismatched/missing kitchenTicketId shows a clear '
      '"not found" state once loading finishes — never an infinite '
      'loading spinner', (tester) async {
    await pumpScreen(tester, kitchenTicketIdToOpen: 'ticket-does-not-exist');

    expect(find.text('Sipariş bulunamadı.'), findsOneWidget);
    expect(find.text('Detaylar yükleniyor...'), findsNothing);
  });

  // 2026-11-08 — previously dineInQr-only; now every channel with a staff
  // cancellation callable (`KitchenActionGateway.cancelOrder`), while the
  // order is still in the kitchen window (confirmed/preparing/ready).
  for (final channel in [
    OrderChannel.dineInQr,
    OrderChannel.takeaway,
    OrderChannel.delivery,
    OrderChannel.reservationPreorder,
  ]) {
    testWidgets(
        '"Siparişi İptal Et" shows for a confirmed ${channel.name} '
        'ticket', (tester) async {
      await pumpScreen(tester,
          ticketChannel: channel, orderStatus: OrderStatus.confirmed);

      expect(find.text('Siparişi İptal Et'), findsOneWidget);
    });
  }

  testWidgets(
      '"Siparişi İptal Et" is absent for dineInStaff (no lifecycle '
      'callable) and for a ticket with no known order status', (tester) async {
    await pumpScreen(tester,
        ticketChannel: OrderChannel.dineInStaff,
        orderStatus: OrderStatus.confirmed);
    expect(find.text('Siparişi İptal Et'), findsNothing);

    await pumpScreen(tester, ticketChannel: OrderChannel.dineInQr);
    expect(find.text('Siparişi İptal Et'), findsNothing);
  });
}
