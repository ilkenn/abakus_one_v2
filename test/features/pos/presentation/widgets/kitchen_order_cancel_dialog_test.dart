import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/staff_reason_rule.dart';
import 'package:abakus_one_v2/features/pos/presentation/widgets/kitchen_order_cancel_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADR-085 stage 6C-2 — every staff cancellation carries a written reason.
void main() {
  Future<KitchenOrderCancellation?> open(
      WidgetTester tester, Future<void> Function() interact) async {
    KitchenOrderCancellation? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => result = await showKitchenOrderCancelDialog(
              context,
              channel: OrderChannel.delivery),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact();
    return result;
  }

  testWidgets('a reason shorter than 5 characters keeps the dialog open',
      (tester) async {
    final result = await open(tester, () async {
      await tester.enterText(
          find.byKey(const Key('orderCancelReasonMessage')), ' ab ');
      await tester.tap(find.byKey(const Key('orderCancelConfirm')));
      await tester.pumpAndSettle();
    });
    expect(result, isNull);
    expect(
        find.text('En az 5 karakterlik bir açıklama yazın.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('returns the chosen code and the trimmed reason', (tester) async {
    final result = await open(tester, () async {
      await tester.tap(find.text('Müşteri gelmedi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('orderCancelReasonMessage')),
          '  Kapıda kimse yok  ');
      await tester.tap(find.byKey(const Key('orderCancelConfirm')));
      await tester.pumpAndSettle();
    });
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, (
      reasonCode: DineInCancellationReasonCode.guestLeft,
      reasonMessage: 'Kapıda kimse yok',
    ));
  });

  test('the shared reason rule', () {
    expect(minStaffReasonLength, 5);
    expect(staffReasonError('abcd'), isNotNull);
    expect(staffReasonError('  abcd  '), isNotNull);
    expect(staffReasonError('abcde'), isNull);
    expect(staffReasonError(null), isNotNull);
  });

  test('every reason code has a Turkish label', () {
    for (final code in DineInCancellationReasonCode.values) {
      expect(
          kitchenOrderCancellationReasonLabel(code,
              channel: OrderChannel.delivery),
          isNotEmpty);
    }
  });
}
