import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/pos/data/cash_register_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/meal_card_revenue_line.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/z_report_content.dart';
import 'package:abakus_one_v2/features/printing/domain/esc_pos_z_report_encoder.dart';

/// 2026-11-11 — product owner: on the Z-Raporu, Pluxee / Multinet / Setcard
/// / Edenred each get their own line (cash-up and provider reconciliation),
/// never folded into "Diğer".
void main() {
  const breakdown = [
    MealCardRevenueLine(
        paymentMethodId: 'pluxee',
        displayName: 'Pluxee',
        amountMinorUnits: 4000),
    MealCardRevenueLine(
        paymentMethodId: 'multinet',
        displayName: 'Multinet',
        amountMinorUnits: 5000),
    MealCardRevenueLine(
        paymentMethodId: 'setcard',
        displayName: 'Setcard',
        amountMinorUnits: 0),
    MealCardRevenueLine(
        paymentMethodId: 'edenred',
        displayName: 'Edenred',
        amountMinorUnits: 0),
  ];

  ZReportContent content() => ZReportContent(
        branchDisplayName: 'Abaküs Merkez',
        sessionId: 'sess-1',
        businessDate: '2026-11-11',
        openedAt: DateTime(2026, 11, 11, 9),
        closedAt: DateTime(2026, 11, 11, 23),
        currencySymbol: 'TL',
        openingFloatMinorUnits: 0,
        cashMinorUnits: 10000,
        cardMinorUnits: 20000,
        otherMinorUnits: 500,
        mealCardBreakdown: breakdown,
        totalMinorUnits: 39500,
        expectedAmountMinorUnits: 10000,
        actualAmountMinorUnits: 10000,
        varianceType: 'exact',
        varianceAmountMinorUnits: 0,
      );

  test('the server breakdown is parsed; an older response has none', () {
    final summary = DailyRevenueSummary.fromWire({
      'sessionId': 'sess-1',
      'currencyCode': 'TRY',
      'cashMinorUnits': 10000,
      'cardMinorUnits': 20000,
      'otherMinorUnits': 500,
      'totalMinorUnits': 39500,
      'mealCardBreakdown': [
        {
          'paymentMethodId': 'multinet',
          'displayName': 'Multinet',
          'amountMinorUnits': 5000,
        },
      ],
    });
    expect(summary.mealCardBreakdown.single.displayName, 'Multinet');
    expect(summary.mealCardBreakdown.single.amountMinorUnits, 5000);

    final older = DailyRevenueSummary.fromWire({
      'sessionId': 'sess-1',
      'currencyCode': 'TRY',
      'cashMinorUnits': 0,
      'cardMinorUnits': 0,
      'otherMinorUnits': 0,
      'totalMinorUnits': 0,
    });
    expect(older.mealCardBreakdown, isEmpty);
  });

  test('the preview text lists every brand between Kredi Kartı and Diğer', () {
    final lines = content().toReceiptText().split('\n');
    final card = lines.indexWhere((l) => l.startsWith('Kredi Kartı:'));
    final other = lines.indexWhere((l) => l.startsWith('Diğer:'));
    expect(lines.sublist(card + 1, other), [
      'Pluxee: TL40.00',
      'Multinet: TL50.00',
      'Setcard: TL0.00',
      'Edenred: TL0.00',
    ]);
  });

  test('the printed Z report has a line per brand', () {
    final text = latin1.decode(
      EscPosZReportEncoder.encode(content()).where((b) => b < 256).toList(),
      allowInvalid: true,
    );
    for (final brand in ['Pluxee', 'Multinet', 'Setcard', 'Edenred']) {
      expect(text, contains(brand));
    }
    expect(text, contains('TL50.00'));
  });
}
