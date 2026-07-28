import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_cash_movement.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/reverse_cash_movement.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement_type.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_opening.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  test(
      'appends an offsetting correction movement, leaving the original untouched',
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
    final auditRepository = InMemoryCashAuditEntryRepository();
    final idGenerator = SequentialCashMovementIdGenerator();
    final original = await RecordCashMovement(
      clock: FakeClock(DateTime(2026, 7, 29, 12)),
      idGenerator: idGenerator,
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      auditRepository: auditRepository,
    )(
      sessionId: 'session-1',
      type: CashMovementType.cashSale,
      amount: Money.fromWhole(100, Currency.tryLira),
      reason: 'Bowl satışı',
      actorStaffId: 'staff-1',
    );

    final reversal = await ReverseCashMovement(
      clock: FakeClock(DateTime(2026, 7, 29, 12, 5)),
      idGenerator: idGenerator,
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      auditRepository: auditRepository,
    )(
      sessionId: 'session-1',
      movementId: original.id,
      reason: 'Yanlış girildi',
      actorStaffId: 'staff-2',
    );

    expect(reversal.type, CashMovementType.correction);
    expect(reversal.amount, Money.fromWhole(-100, Currency.tryLira));
    expect(reversal.reversalOfMovementId, original.id);

    final storedOriginal = await movementRepository.findById(original.id);
    expect(storedOriginal!.amount, Money.fromWhole(100, Currency.tryLira));

    final events = await auditRepository.findBySessionId('session-1');
    expect(
      events.any((e) => e.type == CashAuditEventType.movementReversed),
      isTrue,
    );
  });

  test(
      'throws UnknownCashEntityViolation for a movement from a different session',
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
    final useCase = ReverseCashMovement(
      clock: FakeClock(DateTime(2026, 7, 29)),
      idGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(
        sessionId: 'session-1',
        movementId: 'missing',
        reason: 'x',
        actorStaffId: 'staff-1',
      ),
      throwsA(isA<UnknownCashEntityViolation>()),
    );
  });
}
