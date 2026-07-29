import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kitchen_ticket_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/delayed_orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/kds_test_fixtures.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required InMemoryKitchenTicketRepository ticketRepository,
    required InMemoryKitchenProjectionRepository projectionRepository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kitchenTicketRepositoryProvider.overrideWithValue(ticketRepository),
          kitchenProjectionRepositoryProvider
              .overrideWithValue(projectionRepository),
        ],
        child: const MaterialApp(
          home: DelayedOrdersScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'lists an order whose fixture queuedAt is long past as '
      'delayed (the screen reads the real clock, so a fixed historical '
      'timestamp is always overdue — deterministic, not flaky)',
      (tester) async {
    final ticketRepository = InMemoryKitchenTicketRepository();
    await ticketRepository.save(buildTestKitchenTicket());
    final projectionRepository = InMemoryKitchenProjectionRepository();
    await projectionRepository.save(buildTestKitchenWorkItem(
      status: KitchenLineStatus.queued,
    ));

    await pumpScreen(
      tester,
      ticketRepository: ticketRepository,
      projectionRepository: projectionRepository,
    );

    expect(find.text('ORD-1'), findsOneWidget);
  });

  testWidgets('an empty branch shows the empty-state view', (tester) async {
    await pumpScreen(
      tester,
      ticketRepository: InMemoryKitchenTicketRepository(),
      projectionRepository: InMemoryKitchenProjectionRepository(),
    );

    expect(find.text('Geciken sipariş yok'), findsOneWidget);
  });
}
