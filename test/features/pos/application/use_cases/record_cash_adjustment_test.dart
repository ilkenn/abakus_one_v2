import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_adjustment_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_cash_adjustment.dart';
import 'package:abakus_one_v2/features/pos/data/cash_adjustment_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement_type.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';
import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  test('records a linked correction movement and adjustment', () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession());
    final movementRepository = InMemoryCashMovementRepository();
    final adjustmentRepository = InMemoryCashAdjustmentRepository();
    final auditRepository = InMemoryCashAuditEntryRepository();
    final useCase = RecordCashAdjustment(
      clock: FakeClock(DateTime(2026, 7, 29, 14)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      adjustmentIdGenerator: SequentialCashAdjustmentIdGenerator(),
      movementIdGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      adjustmentRepository: adjustmentRepository,
      auditRepository: auditRepository,
    );

    final adjustment = await useCase(
      sessionId: 'session-1',
      amount: Money.fromWhole(-10, Currency.tryLira),
      reason: 'Yanlış para üstü',
      requestedByStaffId: 'staff-1',
      approvedByStaffId: 'manager-1',
    );

    final movement = await movementRepository.findById(adjustment.movementId);
    expect(movement!.type, CashMovementType.correction);
    expect(movement.amount, Money.fromWhole(-10, Currency.tryLira));

    final events = await auditRepository.findBySessionId('session-1');
    expect(
      events.any((e) => e.type == CashAuditEventType.manualAdjustment),
      isTrue,
    );
  });

  test(
      'throws SelfApprovalNotAllowedViolation when requester approves their own adjustment',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession());
    final useCase = RecordCashAdjustment(
      clock: FakeClock(DateTime(2026, 7, 29, 14)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      adjustmentIdGenerator: SequentialCashAdjustmentIdGenerator(),
      movementIdGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      adjustmentRepository: InMemoryCashAdjustmentRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(
        sessionId: 'session-1',
        amount: Money.fromWhole(-10, Currency.tryLira),
        reason: 'x',
        requestedByStaffId: 'staff-1',
        approvedByStaffId: 'staff-1',
      ),
      throwsA(isA<SelfApprovalNotAllowedViolation>()),
    );
  });

  test('throws AuthorizationDeniedViolation when denied', () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession());
    final useCase = RecordCashAdjustment(
      clock: FakeClock(DateTime(2026, 7, 29, 14)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: false)),
      adjustmentIdGenerator: SequentialCashAdjustmentIdGenerator(),
      movementIdGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      adjustmentRepository: InMemoryCashAdjustmentRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(
        sessionId: 'session-1',
        amount: Money.fromWhole(-10, Currency.tryLira),
        reason: 'x',
        requestedByStaffId: 'staff-1',
        approvedByStaffId: 'manager-1',
      ),
      throwsA(isA<AuthorizationDeniedViolation>()),
    );
  });
}
