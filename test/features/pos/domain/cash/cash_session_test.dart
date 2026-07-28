import 'package:abakus_one_v2/features/pos/domain/cash/cash_closing.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_opening.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

CashSession _session({CashSessionStatus status = CashSessionStatus.active}) {
  return CashSession(
    id: 'session-1',
    drawerId: 'drawer-1',
    branchId: 'branch-1',
    status: status,
    opening: CashOpening(
      openedByStaffId: 'staff-1',
      openedAt: DateTime(2026, 7, 29),
      openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
    ),
    revision: 1,
  );
}

void main() {
  test('isActive is true for every non-closed status', () {
    expect(_session(status: CashSessionStatus.active).isActive, isTrue);
    expect(
        _session(status: CashSessionStatus.pendingApproval).isActive, isTrue);
    expect(_session(status: CashSessionStatus.approved).isActive, isTrue);
  });

  test('isActive is false once closed', () {
    expect(_session(status: CashSessionStatus.closed).isActive, isFalse);
  });

  test('copyWith updates status/closing/revision independently', () {
    final session = _session();
    final closing = CashClosing(
      closedByStaffId: 'staff-2',
      closedAt: DateTime(2026, 7, 29, 22),
      finalCashCountId: 'count-1',
      reconciliationId: 'recon-1',
    );

    final closed = session.copyWith(
      status: CashSessionStatus.closed,
      closing: closing,
      revision: 5,
    );

    expect(closed.status, CashSessionStatus.closed);
    expect(closed.closing, closing);
    expect(closed.revision, 5);
    expect(closed.opening, session.opening);
    expect(closed.id, session.id);
  });
}
