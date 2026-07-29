import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/close_courier_settlement_session.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/courier_settlement_test_fixtures.dart';
import '../../test_support/fake_clock.dart';

void main() {
  group('CloseCourierSettlementSession', () {
    test('closes an approved session and stamps closedAt', () async {
      final sessionRepository = InMemoryCourierSettlementSessionRepository();
      await sessionRepository.save(buildTestCourierSettlementSession(
        status: CourierSettlementSessionStatus.approved,
      ));
      final useCase = CloseCourierSettlementSession(
        clock: FakeClock(DateTime(2026, 7, 30, 10)),
        sessionRepository: sessionRepository,
        auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
      );

      final closed = await useCase(
        settlementSessionId: 'csession-1',
        closedByStaffId: 'manager-1',
      );

      expect(closed.status, CourierSettlementSessionStatus.closed);
      expect(closed.closedAt, DateTime(2026, 7, 30, 10));
    });

    test('throws when the session is not approved', () async {
      final sessionRepository = InMemoryCourierSettlementSessionRepository();
      await sessionRepository.save(buildTestCourierSettlementSession());
      final useCase = CloseCourierSettlementSession(
        clock: FakeClock(DateTime(2026, 7, 30, 10)),
        sessionRepository: sessionRepository,
        auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
      );

      expect(
        () => useCase(
          settlementSessionId: 'csession-1',
          closedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidCourierSettlementSessionTransitionViolation>()),
      );
    });
  });
}
