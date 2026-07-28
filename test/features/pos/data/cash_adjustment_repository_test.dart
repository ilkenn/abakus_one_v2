import 'package:abakus_one_v2/features/pos/data/cash_adjustment_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_adjustment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('append then findBySessionId returns every adjustment', () async {
    final repository = InMemoryCashAdjustmentRepository();
    await repository.append(CashAdjustment(
      id: 'adjustment-1',
      sessionId: 'session-1',
      movementId: 'movement-1',
      reason: 'Kasa farkı',
      requestedByStaffId: 'staff-1',
      approvedByStaffId: 'manager-1',
      createdAt: DateTime(2026, 7, 29),
    ));

    final results = await repository.findBySessionId('session-1');

    expect(results, hasLength(1));
    expect(results.single.movementId, 'movement-1');
    expect(await repository.findBySessionId('session-2'), isEmpty);
  });
}
