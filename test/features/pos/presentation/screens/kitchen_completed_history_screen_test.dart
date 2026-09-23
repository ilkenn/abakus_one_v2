import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_work_item.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/kitchen_completed_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_pos_authorization_policy.dart';
import '../../test_support/kds_test_fixtures.dart';

void main() {
  Future<KitchenProjectionRepository> pumpScreen(
    WidgetTester tester, {
    List<KitchenWorkItem> seedWorkItems = const [],
    PosAuthorizationPolicy? authorizationPolicy,
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
        child: MaterialApp(
          home: KitchenCompletedHistoryScreen(
            branchId: 'branch-1',
            authorizationPolicy: authorizationPolicy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
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

  // 2026-09-22 — recall from this history list, the one remaining place a
  // "mistakenly completed" ticket (order status already advanced past
  // `ready`, so `KitchenOrderDetailsScreen` can no longer resolve it) is
  // still reachable at all.
  testWidgets(
      'the Geri Çağır action only appears for ready items, never terminal ones',
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
    ]);

    expect(find.widgetWithText(TextButton, 'Geri Çağır'), findsOneWidget,
        reason: 'cancelled/unavailable/wasted are terminal — '
            'KitchenLineStatusTransitions has no way back from them');
  });

  testWidgets(
      'recalling a ready item transitions it and removes it from this list',
      (tester) async {
    final repository = await pumpScreen(tester, seedWorkItems: [
      buildTestKitchenWorkItem(
        workItemId: 'w1',
        kitchenTicketLineId: 'line-ready',
        status: KitchenLineStatus.ready,
      ),
    ], authorizationPolicy: FakePosAuthorizationPolicy(
      const AuthorizationResult(granted: true),
    ));

    await tester.tap(find.widgetWithText(TextButton, 'Geri Çağır'));
    await tester.pumpAndSettle();
    // The reason dialog.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(find.text('line-ready'), findsNothing,
        reason: 'a recalled item no longer matches this screen\'s own '
            'ready/cancelled/unavailable/wasted filter');
    expect(find.text('Henüz tamamlanan sipariş yok'), findsOneWidget);

    final recalled = await repository.findById('w1');
    expect(recalled?.status, KitchenLineStatus.recalled);
  });

  testWidgets(
      'recalling without an authorization policy shows a clear message, never a silent no-op or a crash',
      (tester) async {
    await pumpScreen(tester, seedWorkItems: [
      buildTestKitchenWorkItem(
        workItemId: 'w1',
        kitchenTicketLineId: 'line-ready',
        status: KitchenLineStatus.ready,
      ),
    ]); // authorizationPolicy deliberately omitted (null).

    // No policy means no reason dialog even opens — checked first, same
    // as `KitchenOrderDetailsScreen._transition`'s own precedent.
    await tester.tap(find.widgetWithText(TextButton, 'Geri Çağır'));
    await tester.pumpAndSettle();

    expect(find.text('Yetki politikası tanımlı değil.'), findsOneWidget);
    expect(find.text('line-ready'), findsOneWidget,
        reason: 'never silently removed without a real, authorized transition');
  });
}
