import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_settlement_session_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/open_courier_settlement_session.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  group('OpenCourierSettlementSession', () {
    test('opens a new active session at revision 1', () async {
      final repository = InMemoryCourierSettlementSessionRepository();
      final useCase = OpenCourierSettlementSession(
        clock: FakeClock(DateTime(2026, 7, 29, 9)),
        idGenerator: SequentialCourierSettlementSessionIdGenerator(),
        sessionRepository: repository,
      );

      final session =
          await useCase(courierId: 'courier-1', branchId: 'branch-1');

      expect(session.status, CourierSettlementSessionStatus.active);
      expect(session.revision, 1);
      expect(session.courierId, 'courier-1');
    });

    test('throws when the courier already has an active session', () async {
      final repository = InMemoryCourierSettlementSessionRepository();
      final useCase = OpenCourierSettlementSession(
        clock: FakeClock(DateTime(2026, 7, 29, 9)),
        idGenerator: SequentialCourierSettlementSessionIdGenerator(),
        sessionRepository: repository,
      );
      await useCase(courierId: 'courier-1', branchId: 'branch-1');

      expect(
        () => useCase(courierId: 'courier-1', branchId: 'branch-1'),
        throwsA(isA<CourierSettlementSessionAlreadyActiveViolation>()),
      );
    });
  });
}
