import 'package:abakus_one_v2/features/pos/data/courier_cash_collection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_settlement_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/courier_cash_declaration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/courier_settlement_test_fixtures.dart';

void main() {
  Future<InMemoryCourierSettlementSessionRepository> pumpScreen(
      WidgetTester tester) async {
    final sessionRepository = InMemoryCourierSettlementSessionRepository();
    await sessionRepository.save(buildTestCourierSettlementSession());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courierSettlementSessionRepositoryProvider
              .overrideWithValue(sessionRepository),
          courierCashCollectionRepositoryProvider
              .overrideWithValue(InMemoryCourierCashCollectionRepository()),
        ],
        child: const MaterialApp(
          home: CourierCashDeclarationScreen(settlementSessionId: 'csession-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sessionRepository;
  }

  testWidgets('shows a validation error for a non-numeric amount',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Bildirimi Gönder'));
    await tester.pumpAndSettle();

    expect(find.text('Geçerli bir tutar girin'), findsOneWidget);
  });

  testWidgets(
      'submitting a valid declaration moves the session to '
      'pendingApproval', (tester) async {
    final sessionRepository = await pumpScreen(tester);

    await tester.enterText(find.byType(TextField).first, '0');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Bildirimi Gönder'));
    await tester.pumpAndSettle();

    expect(find.text('Bildirim gönderildi. Yönetici onayı bekleniyor.'),
        findsOneWidget);
    final session = await sessionRepository.findById('csession-1');
    expect(session!.status, CourierSettlementSessionStatus.pendingApproval);
  });
}
