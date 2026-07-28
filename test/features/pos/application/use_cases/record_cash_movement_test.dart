import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_cash_movement.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement_type.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_opening.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

CashSession _buildSession(
    {CashSessionStatus status = CashSessionStatus.active}) {
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
  test('an inflow type (cashSale) is recorded as a positive amount', () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(_buildSession());
    final movementRepository = InMemoryCashMovementRepository();
    final useCase = RecordCashMovement(
      clock: FakeClock(DateTime(2026, 7, 29, 12)),
      idGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    final movement = await useCase(
      sessionId: 'session-1',
      type: CashMovementType.cashSale,
      amount: Money.fromWhole(100, Currency.tryLira),
      reason: 'Bowl satışı',
      actorStaffId: 'staff-1',
    );

    expect(movement.amount, Money.fromWhole(100, Currency.tryLira));
  });

  test('an outflow type (manualOut) is recorded as a negative amount',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(_buildSession());
    final useCase = RecordCashMovement(
      clock: FakeClock(DateTime(2026, 7, 29, 12)),
      idGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    final movement = await useCase(
      sessionId: 'session-1',
      type: CashMovementType.manualOut,
      amount: Money.fromWhole(50, Currency.tryLira),
      reason: 'Kurye ödemesi',
      actorStaffId: 'staff-1',
    );

    expect(movement.amount, Money.fromWhole(-50, Currency.tryLira));
  });

  test('rejects a negative amount for a fixed-direction type', () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(_buildSession());
    final useCase = RecordCashMovement(
      clock: FakeClock(DateTime(2026, 7, 29, 12)),
      idGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(
        sessionId: 'session-1',
        type: CashMovementType.cashSale,
        amount: Money.fromWhole(-100, Currency.tryLira),
        reason: 'invalid',
        actorStaffId: 'staff-1',
      ),
      throwsA(isA<NegativeAmountViolation>()),
    );
  });

  test(
      'throws CashSessionNotActiveViolation once the session is no longer active',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository
        .save(_buildSession(status: CashSessionStatus.pendingApproval));
    final useCase = RecordCashMovement(
      clock: FakeClock(DateTime(2026, 7, 29, 12)),
      idGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(
        sessionId: 'session-1',
        type: CashMovementType.cashSale,
        amount: Money.fromWhole(100, Currency.tryLira),
        reason: 'too late',
        actorStaffId: 'staff-1',
      ),
      throwsA(isA<CashSessionNotActiveViolation>()),
    );
  });
}
