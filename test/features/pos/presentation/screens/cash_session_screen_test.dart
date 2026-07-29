import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement_type.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/cash_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/cash_session_screen.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';

void main() {
  Future<InMemoryCashMovementRepository> pumpScreen(
    WidgetTester tester, {
    List<CashMovement> seedMovements = const [],
  }) async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession(sessionId: 'session-1'));
    final movementRepository = InMemoryCashMovementRepository();
    for (final movement in seedMovements) {
      await movementRepository.append(movement);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cashSessionRepositoryProvider.overrideWithValue(sessionRepository),
          cashMovementRepositoryProvider.overrideWithValue(movementRepository),
        ],
        child: const MaterialApp(
          home: CashSessionScreen(sessionId: 'session-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return movementRepository;
  }

  testWidgets('shows the session status and an empty state with no movements',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Durum: active'), findsOneWidget);
    expect(find.text('Henüz kasa hareketi yok'), findsOneWidget);
  });

  testWidgets('lists recorded movements', (tester) async {
    await pumpScreen(tester, seedMovements: [
      CashMovement(
        id: 'movement-1',
        sessionId: 'session-1',
        drawerId: 'drawer-1',
        type: CashMovementType.cashSale,
        amount: Money.fromWhole(50, Currency.tryLira),
        reason: 'Satış',
        actorStaffId: 'staff-1',
        timestamp: DateTime(2026, 7, 29, 10),
      ),
    ]);

    expect(find.text('cashSale'), findsOneWidget);
    expect(find.text('Satış'), findsOneWidget);
    expect(find.text('50.00'), findsOneWidget);
  });

  testWidgets('adding a movement via the dialog appends it', (tester) async {
    final repository = await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Tutar (₺)'), '100');
    await tester.enterText(
        find.widgetWithText(TextField, 'Açıklama'), 'Nakit satış');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ekle'));
    await tester.pumpAndSettle();

    final movements = await repository.findBySessionId('session-1');
    expect(movements, hasLength(1));
    expect(movements.single.reason, 'Nakit satış');
  });

  testWidgets('the count action navigates to the cash count screen',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sayım Yap'));
    await tester.pumpAndSettle();

    expect(find.text('Kasa Sayımı'), findsOneWidget);
  });
}
