import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_work_item.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/kitchen_completed_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/kds_test_fixtures.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    List<KitchenWorkItem> seedWorkItems = const [],
  }) async {
    final repository = InMemoryKitchenProjectionRepository();
    for (final item in seedWorkItems) {
      await repository.save(item);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kitchenProjectionRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: KitchenCompletedHistoryScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty branch shows the empty-state view', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Henüz tamamlanan sipariş yok'), findsOneWidget);
  });

  testWidgets('lists ready and cancelled items, excludes still-active ones',
      (tester) async {
    await pumpScreen(tester, seedWorkItems: [
      buildTestKitchenWorkItem(
        workItemId: 'w1',
        kitchenTicketLineId: 'line-ready',
        status: KitchenLineStatus.ready,
      ),
      buildTestKitchenWorkItem(
        workItemId: 'w2',
        kitchenTicketLineId: 'line-cancelled',
        status: KitchenLineStatus.cancelled,
      ),
      buildTestKitchenWorkItem(
        workItemId: 'w3',
        kitchenTicketLineId: 'line-preparing',
        status: KitchenLineStatus.preparing,
      ),
    ]);

    expect(find.text('line-ready'), findsOneWidget);
    expect(find.text('line-cancelled'), findsOneWidget);
    expect(find.text('line-preparing'), findsNothing);
  });
}
