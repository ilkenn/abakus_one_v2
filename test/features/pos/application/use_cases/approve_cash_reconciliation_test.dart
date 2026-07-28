import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_reconciliation_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/approve_cash_reconciliation.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_count_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_reconciliation_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_reconciliation.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';
import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  test('approves and transitions the session to approved', () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession());
    final countRepository = InMemoryCashCountRepository();
    await submitTestCashCount(
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      countRepository: countRepository,
      sessionId: 'session-1',
      actualAmount: Money.fromWhole(500, Currency.tryLira),
      declaredByStaffId: 'staff-1',
    );

    final useCase = ApproveCashReconciliation(
      clock: FakeClock(DateTime(2026, 7, 29, 23)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      idGenerator: SequentialCashReconciliationIdGenerator(),
      sessionRepository: sessionRepository,
      countRepository: countRepository,
      reconciliationRepository: InMemoryCashReconciliationRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    final reconciliation = await useCase(
      sessionId: 'session-1',
      reviewedByStaffId: 'manager-1',
      managerComments: 'Tamam',
    );

    expect(reconciliation.status, CashReconciliationStatus.approved);
    final updated = await sessionRepository.findById('session-1');
    expect(updated!.status, CashSessionStatus.approved);
  });

  test(
      'throws SelfApprovalNotAllowedViolation when the reviewer declared the count',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession());
    final countRepository = InMemoryCashCountRepository();
    await submitTestCashCount(
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      countRepository: countRepository,
      sessionId: 'session-1',
      actualAmount: Money.fromWhole(500, Currency.tryLira),
      declaredByStaffId: 'staff-1',
    );
    final useCase = ApproveCashReconciliation(
      clock: FakeClock(DateTime(2026, 7, 29, 23)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      idGenerator: SequentialCashReconciliationIdGenerator(),
      sessionRepository: sessionRepository,
      countRepository: countRepository,
      reconciliationRepository: InMemoryCashReconciliationRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(
        sessionId: 'session-1',
        reviewedByStaffId: 'staff-1',
      ),
      throwsA(isA<SelfApprovalNotAllowedViolation>()),
    );
  });

  test('throws AuthorizationDeniedViolation when the policy denies it',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession());
    final countRepository = InMemoryCashCountRepository();
    await submitTestCashCount(
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      countRepository: countRepository,
      sessionId: 'session-1',
      actualAmount: Money.fromWhole(500, Currency.tryLira),
      declaredByStaffId: 'staff-1',
    );
    final useCase = ApproveCashReconciliation(
      clock: FakeClock(DateTime(2026, 7, 29, 23)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: false)),
      idGenerator: SequentialCashReconciliationIdGenerator(),
      sessionRepository: sessionRepository,
      countRepository: countRepository,
      reconciliationRepository: InMemoryCashReconciliationRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(sessionId: 'session-1', reviewedByStaffId: 'manager-1'),
      throwsA(isA<AuthorizationDeniedViolation>()),
    );
  });

  test('throws InvalidCashSessionTransitionViolation when no count is pending',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession());
    final useCase = ApproveCashReconciliation(
      clock: FakeClock(DateTime(2026, 7, 29, 23)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      idGenerator: SequentialCashReconciliationIdGenerator(),
      sessionRepository: sessionRepository,
      countRepository: InMemoryCashCountRepository(),
      reconciliationRepository: InMemoryCashReconciliationRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(sessionId: 'session-1', reviewedByStaffId: 'manager-1'),
      throwsA(isA<InvalidCashSessionTransitionViolation>()),
    );
  });
}
