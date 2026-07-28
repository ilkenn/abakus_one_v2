import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_reconciliation_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/reject_cash_reconciliation.dart';
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
  test(
      'rejects, transitions the session to rejected, and a fresh count can be resubmitted directly',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession());
    final movementRepository = InMemoryCashMovementRepository();
    final countRepository = InMemoryCashCountRepository();
    await submitTestCashCount(
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      countRepository: countRepository,
      sessionId: 'session-1',
      actualAmount: Money.fromWhole(480, Currency.tryLira),
      declaredByStaffId: 'staff-1',
    );

    final useCase = RejectCashReconciliation(
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
      managerComments: 'Tekrar say',
    );

    expect(reconciliation.status, CashReconciliationStatus.rejected);
    final rejectedSession = await sessionRepository.findById('session-1');
    expect(rejectedSession!.status, CashSessionStatus.rejected);

    // A recount is submittable directly from rejected — no separate
    // reactivate step.
    final recount = await submitTestCashCount(
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      countRepository: countRepository,
      sessionId: 'session-1',
      actualAmount: Money.fromWhole(500, Currency.tryLira),
      declaredByStaffId: 'staff-1',
    );

    expect(recount.declaration.actualAmount,
        Money.fromWhole(500, Currency.tryLira));
    final resubmittedSession = await sessionRepository.findById('session-1');
    expect(resubmittedSession!.status, CashSessionStatus.pendingApproval);
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
    final useCase = RejectCashReconciliation(
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
        managerComments: 'x',
      ),
      throwsA(isA<SelfApprovalNotAllowedViolation>()),
    );
  });
}
