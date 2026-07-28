import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_reconciliation_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/approve_cash_reconciliation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/close_cash_session.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_count_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_reconciliation_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';
import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  test('closes an approved session and records the closing link', () async {
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
    final reconciliationRepository = InMemoryCashReconciliationRepository();
    final reconciliation = await ApproveCashReconciliation(
      clock: FakeClock(DateTime(2026, 7, 29, 23)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      idGenerator: SequentialCashReconciliationIdGenerator(),
      sessionRepository: sessionRepository,
      countRepository: countRepository,
      reconciliationRepository: reconciliationRepository,
      auditRepository: InMemoryCashAuditEntryRepository(),
    )(sessionId: 'session-1', reviewedByStaffId: 'manager-1');

    final useCase = CloseCashSession(
      clock: FakeClock(DateTime(2026, 7, 30, 0)),
      sessionRepository: sessionRepository,
      reconciliationRepository: reconciliationRepository,
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    final closed =
        await useCase(sessionId: 'session-1', closedByStaffId: 'manager-1');

    expect(closed.status, CashSessionStatus.closed);
    expect(closed.closing!.reconciliationId, reconciliation.id);
    expect(closed.isActive, isFalse);
  });

  test('throws InvalidCashSessionTransitionViolation when not yet approved',
      () async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession());
    final useCase = CloseCashSession(
      clock: FakeClock(DateTime(2026, 7, 30, 0)),
      sessionRepository: sessionRepository,
      reconciliationRepository: InMemoryCashReconciliationRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    expect(
      () => useCase(sessionId: 'session-1', closedByStaffId: 'manager-1'),
      throwsA(isA<InvalidCashSessionTransitionViolation>()),
    );
  });
}
