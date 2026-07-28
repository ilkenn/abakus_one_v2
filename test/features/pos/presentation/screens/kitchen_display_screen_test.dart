import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_header.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_line.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kitchen_ticket_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/kitchen_display_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  Future<InMemoryKitchenTicketRepository> pumpScreen(
      WidgetTester tester) async {
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
        KitchenTicketLine(
            id: 'line-1', productName: 'Mexifit Bowl', quantity: 1),
      ],
      firedAt: DateTime(2026, 7, 29, 11, 55),
      revision: 1,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 7, 29, 12))),
          kitchenTicketRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: KitchenDisplayScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('shows every fired ticket for the branch', (tester) async {
    await pumpScreen(tester);

    expect(find.text('A-001'), findsOneWidget);
    expect(find.textContaining('Mexifit Bowl'), findsOneWidget);
  });

  testWidgets('tapping a line marks it ready and shows HAZIR once complete',
      (tester) async {
    final repository = await pumpScreen(tester);

    await tester.tap(find.textContaining('Mexifit Bowl'));
    await tester.pumpAndSettle();

    expect(find.text('HAZIR'), findsOneWidget);
    final ticket = await repository.findById('ticket-1');
    expect(ticket!.isFullyReady, isTrue);
  });

  testWidgets('an empty queue shows the empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 7, 29, 12))),
          kitchenTicketRepositoryProvider
              .overrideWithValue(InMemoryKitchenTicketRepository()),
        ],
        child: const MaterialApp(
          home: KitchenDisplayScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bekleyen fiş yok'), findsOneWidget);
  });
}
