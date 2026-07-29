import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/cash_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/cash_count_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';

void main() {
  Future<InMemoryCashSessionRepository> pumpScreen(WidgetTester tester) async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession(sessionId: 'session-1'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cashSessionRepositoryProvider.overrideWithValue(sessionRepository),
          cashMovementRepositoryProvider
              .overrideWithValue(InMemoryCashMovementRepository()),
        ],
        child: const MaterialApp(
          home: CashCountScreen(sessionId: 'session-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sessionRepository;
  }

  testWidgets('shows a validation error for a non-numeric amount',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sayımı Gönder'));
    await tester.pumpAndSettle();

    expect(find.text('Geçerli bir tutar girin'), findsOneWidget);
  });

  testWidgets(
      'submitting a valid count moves the session to pendingApproval and '
      'navigates to reconciliation', (tester) async {
    final sessionRepository = await pumpScreen(tester);

    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sayımı Gönder'));
    await tester.pumpAndSettle();

    expect(find.text('Kasa Mutabakatı'), findsOneWidget);
    final session = await sessionRepository.findById('session-1');
    expect(session!.status, CashSessionStatus.pendingApproval);
  });
}
