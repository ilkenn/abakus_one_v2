import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kitchen_ticket_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/kitchen_display_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/kds_test_fixtures.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required InMemoryKitchenTicketRepository ticketRepository,
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
}
