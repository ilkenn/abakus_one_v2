import 'package:abakus_one_v2/features/pos/data/cash_reconciliation_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

CashReconciliation _reconciliation({
  String id = 'recon-1',
  String sessionId = 'session-1',
  CashReconciliationStatus status = CashReconciliationStatus.approved,
}) {
  return CashReconciliation(
    id: id,
    sessionId: sessionId,
    cashCountId: 'count-1',
    status: status,
    reviewedByStaffId: 'staff-2',
    reviewedAt: DateTime(2026, 7, 29),
  );
}

void main() {
  test('append never overwrites; findBySessionId returns every reconciliation',
      () async {
    final repository = InMemoryCashReconciliationRepository();
    await repository.append(_reconciliation(
        id: 'recon-1', status: CashReconciliationStatus.rejected));
    await repository.append(_reconciliation(id: 'recon-2'));

    final results = await repository.findBySessionId('session-1');

    expect(results.map((r) => r.id), ['recon-1', 'recon-2']);
    // The rejected one remains in history, not deleted.
    expect(results.first.status, CashReconciliationStatus.rejected);
  });

  test(
      'findLatestBySessionId returns the most recently appended reconciliation',
      () async {
    final repository = InMemoryCashReconciliationRepository();
    await repository.append(_reconciliation(id: 'recon-1'));
    await repository.append(_reconciliation(id: 'recon-2'));

    expect(
        (await repository.findLatestBySessionId('session-1'))!.id, 'recon-2');
  });
}
