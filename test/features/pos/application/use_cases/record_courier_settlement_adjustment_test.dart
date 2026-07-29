import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_settlement_adjustment_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_cash_movement.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_courier_settlement_adjustment.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_adjustment_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement_type.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';
import '../../test_support/courier_settlement_test_fixtures.dart';
import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  group('RecordCourierSettlementAdjustment', () {
    late InMemoryCourierSettlementSessionRepository sessionRepository;
    late InMemoryCashSessionRepository cashSessionRepository;
    late InMemoryCashMovementRepository cashMovementRepository;
    late InMemoryCourierSettlementAdjustmentRepository adjustmentRepository;
    late RecordCashMovement recordCashMovement;

    setUp(() async {
      sessionRepository = InMemoryCourierSettlementSessionRepository();
      await sessionRepository.save(buildTestCourierSettlementSession(
        status: CourierSettlementSessionStatus.approved,
      ));
      cashSessionRepository = InMemoryCashSessionRepository();
      await cashSessionRepository
          .save(buildTestCashSession(sessionId: 'cash-session-1'));
      cashMovementRepository = InMemoryCashMovementRepository();
      recordCashMovement = RecordCashMovement(
        clock: FakeClock(DateTime(2026, 7, 30, 11)),
        idGenerator: SequentialCashMovementIdGenerator(),
        sessionRepository: cashSessionRepository,
        movementRepository: cashMovementRepository,
        auditRepository: InMemoryCashAuditEntryRepository(),
      );
      adjustmentRepository = InMemoryCourierSettlementAdjustmentRepository();
    });

    RecordCourierSettlementAdjustment buildUseCase(
        AuthorizationResult authorization) {
      return RecordCourierSettlementAdjustment(
        clock: FakeClock(DateTime(2026, 7, 30, 11)),
        authorizationPolicy: FakePosAuthorizationPolicy(authorization),
        adjustmentIdGenerator:
            SequentialCourierSettlementAdjustmentIdGenerator(),
        sessionRepository: sessionRepository,
        adjustmentRepository: adjustmentRepository,
        auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
        recordCashMovement: recordCashMovement,
      );
    }

    test('records a correction CashMovement linked to a new adjustment',
        () async {
      final useCase = buildUseCase(const AuthorizationResult(granted: true));

      final adjustment = await useCase(
        settlementSessionId: 'csession-1',
        targetCashSessionId: 'cash-session-1',
        amount: Money.fromWhole(10, Currency.tryLira),
        reason: 'Eksik teslimat düzeltmesi',
        requestedByStaffId: 'staff-1',
        approvedByStaffId: 'manager-1',
      );

      final movement =
          await cashMovementRepository.findById(adjustment.movementId);
      expect(movement!.type, CashMovementType.correction);
      final adjustments =
          await adjustmentRepository.findBySettlementSessionId('csession-1');
      expect(adjustments, hasLength(1));
    });

    test('throws when requester and approver are the same', () async {
      final useCase = buildUseCase(const AuthorizationResult(granted: true));

      expect(
        () => useCase(
          settlementSessionId: 'csession-1',
          targetCashSessionId: 'cash-session-1',
          amount: Money.fromWhole(10, Currency.tryLira),
          reason: 'x',
          requestedByStaffId: 'staff-1',
          approvedByStaffId: 'staff-1',
        ),
        throwsA(isA<SelfApprovalNotAllowedViolation>()),
      );
    });

    test('throws once the session is closed', () async {
      await sessionRepository.save(
        (await sessionRepository.findById('csession-1'))!.copyWith(
          status: CourierSettlementSessionStatus.closed,
          revision: 2,
        ),
      );
      final useCase = buildUseCase(const AuthorizationResult(granted: true));

      expect(
        () => useCase(
          settlementSessionId: 'csession-1',
          targetCashSessionId: 'cash-session-1',
          amount: Money.fromWhole(10, Currency.tryLira),
          reason: 'x',
          requestedByStaffId: 'staff-1',
          approvedByStaffId: 'manager-1',
        ),
        throwsA(isA<CourierSettlementSessionNotActiveViolation>()),
      );
    });
  });
}
