import 'package:abakus_one_v2/features/pos/data/courier_cash_collection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/payment_session_repository.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_settlement_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/payment_session_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/courier_settlement_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/courier_settlement_test_fixtures.dart';

void main() {
  Future<
      ({
        InMemoryCourierCashCollectionRepository collections,
      })> pumpScreen(
    WidgetTester tester, {
    required InMemoryPaymentSessionRepository paymentSessionRepository,
  }) async {
    final sessionRepository = InMemoryCourierSettlementSessionRepository();
    await sessionRepository.save(buildTestCourierSettlementSession());
    final collectionRepository = InMemoryCourierCashCollectionRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courierSettlementSessionRepositoryProvider
              .overrideWithValue(sessionRepository),
          courierCashCollectionRepositoryProvider
              .overrideWithValue(collectionRepository),
          paymentSessionRepositoryProvider
              .overrideWithValue(paymentSessionRepository),
        ],
        child: const MaterialApp(
          home:
              CourierSettlementDetailScreen(settlementSessionId: 'csession-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (collections: collectionRepository);
  }

  testWidgets(
      'shows the session status and an empty state with no '
      'collections', (tester) async {
    await pumpScreen(
      tester,
      paymentSessionRepository: InMemoryPaymentSessionRepository(),
    );

    expect(find.text('Durum: active'), findsOneWidget);
    expect(find.text('Henüz tahsilat yok'), findsOneWidget);
  });

  testWidgets('adding a collection via the dialog appends it', (tester) async {
    final paymentSessionRepository = InMemoryPaymentSessionRepository();
    await seedTestPaymentSession(repository: paymentSessionRepository);
    final repos = await pumpScreen(tester,
        paymentSessionRepository: paymentSessionRepository);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Sipariş No'), 'order-1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Ödeme Oturumu No'), 'ps-1');
    await tester.enterText(find.widgetWithText(TextField, 'Tutar (₺)'), '100');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ekle'));
    await tester.pumpAndSettle();

    final collections =
        await repos.collections.findBySettlementSessionId('csession-1');
    expect(collections, hasLength(1));
  });

  testWidgets('the declare action navigates to the declaration screen',
      (tester) async {
    await pumpScreen(
      tester,
      paymentSessionRepository: InMemoryPaymentSessionRepository(),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Kasayı Bildir'));
    await tester.pumpAndSettle();

    expect(find.text('Kasa Bildirimi'), findsOneWidget);
  });
}
