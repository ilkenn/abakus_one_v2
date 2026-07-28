import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_header.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_line.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kitchen_ticket_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/expeditor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  testWidgets('shows a ready order with its wait time', (tester) async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(KitchenTicket(
      id: 'ticket-1',
      orderId: OrderId('order-1'),
      branchId: 'branch-1',
      type: KitchenTicketType.initial,
      header: KitchenTicketHeader(
        restaurantName: 'Abaküs',
        branchName: 'Kadıköy',
        channelLabel: 'Masa',
        orderNumber: 'A-001',
        orderTypeLabel: 'Masa',
        receivedAt: DateTime(2026, 7, 29),
      ),
      lines: const [
        KitchenTicketLine(id: 'line-1', productName: 'Bowl A', quantity: 1),
      ],
      completedLineIds: const ['line-1'],
      orderReadyAt: DateTime(2026, 7, 29, 11, 50),
      firedAt: DateTime(2026, 7, 29),
      revision: 2,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 7, 29, 12))),
          kitchenTicketRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ExpeditorScreen(branchId: 'branch-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A-001'), findsOneWidget);
    expect(find.textContaining('HAZIR'), findsOneWidget);
    expect(find.textContaining('1/1 ürün hazır'), findsOneWidget);
  });

  testWidgets('an empty branch shows the empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 7, 29, 12))),
          kitchenTicketRepositoryProvider
              .overrideWithValue(InMemoryKitchenTicketRepository()),
        ],
        child: const MaterialApp(home: ExpeditorScreen(branchId: 'branch-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bekleyen sipariş yok'), findsOneWidget);
  });
}
