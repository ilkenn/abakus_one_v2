import 'package:abakus_one_v2/features/pos/data/pos_operational_view_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/receipts/table_receipt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-10 — paid modifiers must be part of every POS line amount: the
/// server's check (`computeLineValueMinorUnits`) charges
/// (base + modifiers) × quantity, so the client may never show base × qty.
const _bowlWithExtras = PosOrderLineSummary(
  productId: 'prod_bowl2_aci_soslu_tavuk',
  productName: 'Acı Soslu Tavuk Bowl',
  quantity: 2,
  unitPriceMinorUnits: 52000,
  status: 'accepted',
  subAccountId: null,
  modifiers: [
    PosOrderLineModifierSummary(
      groupName: 'Ekstra Protein',
      optionName: 'Izgara Tavuk (Göğüs)',
      quantity: 1,
      unitExtraPriceMinorUnits: 15000,
    ),
    PosOrderLineModifierSummary(
      groupName: 'Peynir',
      optionName: 'Beyaz Peynir',
      quantity: 2,
      unitExtraPriceMinorUnits: 2000,
    ),
    PosOrderLineModifierSummary(
      groupName: 'Salata Değişimi',
      optionName: 'Roka',
      quantity: 1,
      unitExtraPriceMinorUnits: 0,
    ),
  ],
);

void main() {
  test('line totals include paid modifiers (server formula)', () {
    // 150 + 2 × 20 + 0 = 190 TL of extras per bowl.
    expect(_bowlWithExtras.modifiersExtraMinorUnits, 19000);
    expect(_bowlWithExtras.unitTotalMinorUnits, 71000);
    expect(_bowlWithExtras.lineTotalMinorUnits, 142000);
  });

  test('a line without modifiers is unchanged: base × quantity', () {
    const plain = PosOrderLineSummary(
      productName: 'Coca-Cola Kutu',
      quantity: 3,
      unitPriceMinorUnits: 10000,
      status: 'accepted',
      subAccountId: null,
    );
    expect(plain.unitTotalMinorUnits, 10000);
    expect(plain.lineTotalMinorUnits, 30000);
  });

  test('the till receipt prints modifier-inclusive line amounts', () {
    final receipt = TableReceiptBuilder.build(
      view: const PosTableOperationalView(
        tableId: 'table-1',
        status: 'occupied',
        tableSessionId: 'tsess-1',
        subAccounts: [],
        checks: [
          {'id': 'check-1', 'computedTotalMinorUnits': 142000},
        ],
        orders: [
          PosTableOrderSummary(
            orderId: 'order-1',
            subAccountId: null,
            mode: 'staffGeneral',
            linesDispositionSummary: 'resolved',
            lines: [_bowlWithExtras],
          ),
        ],
      ),
      checkId: 'check-1',
      restaurantName: 'Abaküs',
      branchName: 'Merkez Şube',
      tableName: 'Salon 1',
      receiptNumber: 'R-1',
      issuedAt: DateTime(2026, 11, 10, 12),
      recipeFor: (_) => '',
    );

    expect(receipt.lines.single.unitPriceMinorUnits, 71000);
    expect(receipt.lines.single.totalPriceMinorUnits, 142000);
    // Lines now add up to the check total — no phantom "discount".
    expect(receipt.subtotalMinorUnits, 142000);
    expect(receipt.discountMinorUnits, 0);
    expect(receipt.totalMinorUnits, 142000);
  });
}
