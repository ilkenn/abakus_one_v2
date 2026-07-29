import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_settlement_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/courier_settlement_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/courier_settlement_test_fixtures.dart';

void main() {
  Future<InMemoryCourierSettlementSessionRepository> pumpScreen(
    WidgetTester tester, {
    bool seedSession = false,
  }) async {
    final repository = InMemoryCourierSettlementSessionRepository();
    if (seedSession) {
      await repository.save(buildTestCourierSettlementSession());
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courierSettlementSessionRepositoryProvider
              .overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: CourierSettlementListScreen(courierId: 'courier-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('an empty repository shows the empty-state view', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Henüz vardiya yok'), findsOneWidget);
  });

  testWidgets('lists sessions for the courier', (tester) async {
    await pumpScreen(tester, seedSession: true);

    expect(find.text('csession-1'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
  });

  testWidgets('starting a shift creates a new active session', (tester) async {
    final repository = await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final sessions = await repository.findByCourierId('courier-1');
    expect(sessions, hasLength(1));
  });
}
