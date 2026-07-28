import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_opening.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

CashSession _session({
  String id = 'session-1',
  String drawerId = 'drawer-1',
  CashSessionStatus status = CashSessionStatus.active,
  int revision = 1,
}) {
  return CashSession(
    id: id,
    drawerId: drawerId,
    branchId: 'branch-1',
    status: status,
    opening: CashOpening(
      openedByStaffId: 'staff-1',
      openedAt: DateTime(2026, 7, 29),
      openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
    ),
    revision: revision,
  );
}

void main() {
  test('findById returns the latest revision', () async {
    final repository = InMemoryCashSessionRepository();
    await repository.save(_session(revision: 1));
    await repository
        .save(_session(revision: 2, status: CashSessionStatus.pendingApproval));

    final result = await repository.findById('session-1');

    expect(result!.revision, 2);
    expect(result.status, CashSessionStatus.pendingApproval);
  });

  test('findActiveByDrawerId returns only a non-closed session', () async {
    final repository = InMemoryCashSessionRepository();
    await repository
        .save(_session(id: 'session-1', status: CashSessionStatus.closed));
    await repository
        .save(_session(id: 'session-2', status: CashSessionStatus.active));

    final active = await repository.findActiveByDrawerId('drawer-1');

    expect(active!.id, 'session-2');
  });

  test('findActiveByDrawerId returns null when the only session is closed',
      () async {
    final repository = InMemoryCashSessionRepository();
    await repository.save(_session(status: CashSessionStatus.closed));

    expect(await repository.findActiveByDrawerId('drawer-1'), isNull);
  });

  test(
      'findByDrawerId returns the latest revision of every session for that drawer',
      () async {
    final repository = InMemoryCashSessionRepository();
    await repository.save(_session(id: 'session-1', drawerId: 'drawer-a'));
    await repository.save(_session(id: 'session-2', drawerId: 'drawer-b'));

    final results = await repository.findByDrawerId('drawer-a');

    expect(results.map((s) => s.id), ['session-1']);
  });
}
