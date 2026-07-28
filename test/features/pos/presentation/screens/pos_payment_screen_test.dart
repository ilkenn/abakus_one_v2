import 'package:abakus_one_v2/core/layout/app_breakpoints.dart';
import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/pos/data/payment_session_repository.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/payment_session_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_payment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

Order _buildOrder() {
  return CartToOrderMapper.map(
    orderId: OrderId('order-1'),
    orderNumber: OrderNumber('A-001'),
    cartItems: const [
      CartItem(
          id: 'p1', name: 'Mexifit Bowl', desc: '', price: 194.0, quantity: 1),
    ],
    channel: OrderChannel.dineInStaff,
    branchId: 'branch-1',
    restaurantId: 'restaurant-abakus',
    now: DateTime(2026, 7, 29),
  );
}

void main() {
  late InMemoryPaymentSessionRepository repository;

  Future<void> pumpPayment(
    WidgetTester tester, {
    Size viewportSize = const Size(400, 900),
  }) async {
    tester.view.physicalSize = viewportSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    repository = InMemoryPaymentSessionRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider
              .overrideWithValue(FakeClock(DateTime(2026, 7, 29, 12, 0))),
          paymentSessionRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: PosPaymentScreen(sessionId: 'ps1', order: _buildOrder()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Several controls live inside a scrollable panel and can be pushed
  /// below the phone-width viewport — scroll them into view before
  /// tapping, matching the convention already used in
  /// `pos_cashier_screen_test.dart`.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('PosPaymentScreen — layout', () {
    testWidgets(
        'phone width stacks the summary and collection panels vertically',
        (tester) async {
      await pumpPayment(tester, viewportSize: const Size(400, 900));

      expect(find.byType(VerticalDivider), findsNothing);
      final summaryTop = tester.getTopLeft(find.text('Tahsil Edilen'));
      final methodTop = tester.getTopLeft(find.text('Ödeme Yöntemi'));
      expect(methodTop.dy, greaterThan(summaryTop.dy));
    });

    testWidgets('desktop width places the panels side by side', (tester) async {
      await pumpPayment(
        tester,
        viewportSize: const Size(AppBreakpoints.desktop + 200, 900),
      );

      expect(find.byType(VerticalDivider), findsOneWidget);
    });
  });

  group('PosPaymentScreen — amount highlight', () {
    testWidgets(
        'shows Toplam/Tahsil Edilen/Kalan and updates live after a split',
        (tester) async {
      await pumpPayment(tester);

      expect(find.text('Toplam'), findsOneWidget);
      expect(find.text('Tahsil Edilen'), findsOneWidget);
      expect(find.text('Kalan'), findsOneWidget);
      expect(find.text('Para Üstü'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Tutar'), '100');
      await tapVisible(tester, find.widgetWithText(ElevatedButton, 'Ekle'));

      expect(find.textContaining('TRY 100.00'), findsWidgets);
    });

    testWidgets('a cash overpay shows Para Üstü (change)', (tester) async {
      await pumpPayment(tester);

      // Cash is selected by default; enter more than the 194.00 total.
      final amountField = find.byType(TextField).first;
      await tester.enterText(amountField, '300');
      await tapVisible(tester, find.widgetWithText(ElevatedButton, 'Ekle'));

      expect(find.text('Para Üstü'), findsOneWidget);
    });
  });

  group('PosPaymentScreen — split payment to completion', () {
    testWidgets(
        'completing is disabled until fully settled, then enabled and succeeds',
        (tester) async {
      await pumpPayment(tester);

      final completeButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Ödemeyi Tamamla'),
      );
      expect(completeButton.onPressed, isNull);

      final amountField = find.byType(TextField).first;
      await tester.enterText(amountField, '194');
      await tapVisible(tester, find.widgetWithText(ElevatedButton, 'Ekle'));

      final enabledButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Ödemeyi Tamamla'),
      );
      expect(enabledButton.onPressed, isNotNull);

      await tapVisible(
          tester, find.widgetWithText(ElevatedButton, 'Ödemeyi Tamamla'));

      expect(find.text('Ödeme Tamamlandı'), findsOneWidget);
    });
  });

  group('PosPaymentScreen — calculator', () {
    testWidgets('never changes the amount field until Uygula is tapped',
        (tester) async {
      await pumpPayment(tester);

      await tapVisible(tester, find.byIcon(Icons.calculate_outlined));

      await tester.tap(find.widgetWithText(OutlinedButton, '1'));
      await tester.tap(find.widgetWithText(OutlinedButton, '0'));
      await tester.tap(find.widgetWithText(OutlinedButton, '0'));
      await tester.pumpAndSettle();

      final amountFieldBeforeApply =
          tester.widget<TextField>(find.byType(TextField).first);
      expect(amountFieldBeforeApply.controller!.text, isEmpty);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Uygula'));
      await tester.pumpAndSettle();

      final amountFieldAfterApply =
          tester.widget<TextField>(find.byType(TextField).first);
      expect(amountFieldAfterApply.controller!.text, '100.00');
    });
  });
}
