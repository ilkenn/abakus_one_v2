import 'package:abakus_one_v2/features/courier/domain/settlement/consortium_delivery_settlement.dart';
import 'package:abakus_one_v2/features/courier/domain/settlement/consortium_settlement_status.dart';
import 'package:flutter_test/flutter_test.dart';

ConsortiumDeliverySettlement _buildSettlement() {
  return ConsortiumDeliverySettlement(
    id: 'settlement-1',
    merchantId: 'merchant-a',
    merchantName: 'Dış Restoran A',
    orderId: 'order-1',
    courierId: 'courier-1',
    branchId: 'branch-1',
    deliveryFeeMinorUnits: 5000,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('ConsortiumDeliverySettlement', () {
    test('defaults to pending status and no settledAt', () {
      final settlement = _buildSettlement();
      expect(settlement.status, ConsortiumSettlementStatus.pending);
      expect(settlement.settledAt, isNull);
      expect(settlement.revision, 1);
    });

    test('copyWith updates status/settledAt/revision independently of the rest', () {
      final original = _buildSettlement();
      final settled = original.copyWith(
        status: ConsortiumSettlementStatus.settled,
        settledAt: DateTime(2026, 1, 2),
        revision: 2,
      );

      expect(settled.status, ConsortiumSettlementStatus.settled);
      expect(settled.settledAt, DateTime(2026, 1, 2));
      expect(settled.revision, 2);
      expect(settled.deliveryFeeMinorUnits, 5000);
      expect(settled.merchantId, 'merchant-a');
    });
  });
}
