import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_count_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_cash_movement.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/submit_cash_count.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_count_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement_type.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_opening.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_variance.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  test(
      'computes the expected amount as the sum of all movements and transitions the session to pendingApproval',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(CashSession(
      id: 'session-1',
      drawerId: 'drawer-1',
      branchId: 'branch-1',
      status: CashSessionStatus.active,
      opening: CashOpening(
        openedByStaffId: 'staff-1',
        openedAt: DateTime(2026, 7, 29),
        openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
      ),
      revision: 1,
    ));
    final movementRepository = InMemoryCashMovementRepository();
    // Opening float itself is normally recorded by OpenCashDrawer; here we
    // record it directly plus a sale and a payout to exercise the sum.
    final recordMovement = RecordCashMovement(
      clock: FakeClock(DateTime(2026, 7, 29, 10)),
      idGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      auditRepository: InMemoryCashAuditEntryRepository(),
    );
    await recordMovement(
      sessionId: 'session-1',
      type: CashMovementType.openingFloat,
      amount: Money.fromWhole(500, Currency.tryLira),
      reason: 'Açılış',
      actorStaffId: 'staff-1',
    );
    await recordMovement(
      sessionId: 'session-1',
      type: CashMovementType.cashSale,
      amount: Money.fromWhole(200, Currency.tryLira),
      reason: 'Satış',
      actorStaffId: 'staff-1',
    );
    await recordMovement(
      sessionId: 'session-1',
      type: CashMovementType.manualOut,
      amount: Money.fromWhole(50, Currency.tryLira),
      reason: 'Kurye',
      actorStaffId: 'staff-1',
    );
    // Expected: 500 + 200 - 50 = 650

    final countRepository = InMemoryCashCountRepository();
    final useCase = SubmitCashCount(
      clock: FakeClock(DateTime(2026, 7, 29, 22)),
      idGenerator: SequentialCashCountIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      countRepository: countRepository,
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    final count = await useCase(
      sessionId: 'session-1',
      actualAmount: Money.fromWhole(650, Currency.tryLira),
      declaredByStaffId: 'staff-1',
    );

    expect(count.expectedAmount, Money.fromWhole(650, Currency.tryLira));
    expect(count.variance.isExact, isTrue);

    final updatedSession = await sessionRepository.findById('session-1');
    expect(updatedSession!.status, CashSessionStatus.pendingApproval);
  });

  test('a shortage produces a short CashVariance', () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(CashSession(
      id: 'session-1',
      drawerId: 'drawer-1',
      branchId: 'branch-1',
      status: CashSessionStatus.active,
      opening: CashOpening(
        openedByStaffId: 'staff-1',
        openedAt: DateTime(2026, 7, 29),
        openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
      ),
      revision: 1,
    ));
    final movementRepository = InMemoryCashMovementRepository();
    await RecordCashMovement(
      clock: FakeClock(DateTime(2026, 7, 29, 10)),
      idGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      auditRepository: InMemoryCashAuditEntryRepository(),
    )(
      sessionId: 'session-1',
      type: CashMovementType.openingFloat,
      amount: Money.fromWhole(500, Currency.tryLira),
      reason: 'Açılış',
      actorStaffId: 'staff-1',
    );

    final useCase = SubmitCashCount(
      clock: FakeClock(DateTime(2026, 7, 29, 22)),
      idGenerator: SequentialCashCountIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      countRepository: InMemoryCashCountRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    final count = await useCase(
      sessionId: 'session-1',
      actualAmount: Money.fromWhole(480, Currency.tryLira),
      declaredByStaffId: 'staff-1',
    );

    expect(count.variance.type, CashVarianceType.short);
    expect(count.variance.amount, Money.fromWhole(20, Currency.tryLira));
  });

  test('throws CashSessionNotActiveViolation once a count is already pending',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(CashSession(
      id: 'session-1',
      drawerId: 'drawer-1',
      branchId: 'branch-1',
      status: CashSessionStatus.pendingApproval,
      opening: CashOpening(
        openedByStaffId: 'staff-1',
        openedAt: DateTime(2026, 7, 29),
        openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
      ),
      revision: 2,
    ));
    final useCase = SubmitCashCount(
      clock: FakeClock(DateTime(2026, 7, 29, 22)),
      idGenerator: SequentialCashCountIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      countRepository: InMemoryCashCountRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(
        sessionId: 'session-1',
        actualAmount: Money.fromWhole(500, Currency.tryLira),
        declaredByStaffId: 'staff-1',
      ),
      throwsA(isA<CashSessionNotActiveViolation>()),
    );
  });
}
