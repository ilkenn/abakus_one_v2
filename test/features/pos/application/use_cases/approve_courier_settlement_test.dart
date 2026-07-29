import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_settlement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/approve_courier_settlement.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_cash_movement.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_declaration_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement_type.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_cash_declaration.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_status.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_variance.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';
import '../../test_support/courier_settlement_test_fixtures.dart';
import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  group('ApproveCourierSettlement', () {
    late InMemoryCourierSettlementSessionRepository sessionRepository;
    late InMemoryCourierCashDeclarationRepository declarationRepository;
    late InMemoryCourierSettlementRepository settlementRepository;
    late InMemoryCashSessionRepository cashSessionRepository;
    late InMemoryCashMovementRepository cashMovementRepository;
    late RecordCashMovement recordCashMovement;

    setUp(() async {
      sessionRepository = InMemoryCourierSettlementSessionRepository();
      await sessionRepository.save(buildTestCourierSettlementSession(
        status: CourierSettlementSessionStatus.pendingApproval,
      ));
      declarationRepository = InMemoryCourierCashDeclarationRepository();
      await declarationRepository.append(CourierCashDeclaration(
        id: 'cdeclaration-1',
        settlementSessionId: 'csession-1',
        courierId: 'courier-1',
        expectedAmount: Money.fromWhole(200, Currency.tryLira),
        declaredAmount: Money.fromWhole(200, Currency.tryLira),
        variance: CourierSettlementVariance.compute(
          expectedAmount: Money.fromWhole(200, Currency.tryLira),
          declaredAmount: Money.fromWhole(200, Currency.tryLira),
        ),
        declaredAt: DateTime(2026, 7, 29, 22),
      ));
      settlementRepository = InMemoryCourierSettlementRepository();

      cashSessionRepository = InMemoryCashSessionRepository();
      await cashSessionRepository
          .save(buildTestCashSession(sessionId: 'cash-session-1'));
      cashMovementRepository = InMemoryCashMovementRepository();
      recordCashMovement = RecordCashMovement(
        clock: FakeClock(DateTime(2026, 7, 29, 23)),
        idGenerator: SequentialCashMovementIdGenerator(),
        sessionRepository: cashSessionRepository,
        movementRepository: cashMovementRepository,
        auditRepository: InMemoryCashAuditEntryRepository(),
      );
    });

    ApproveCourierSettlement buildUseCase(AuthorizationResult authorization) {
      return ApproveCourierSettlement(
        clock: FakeClock(DateTime(2026, 7, 30, 9)),
        authorizationPolicy: FakePosAuthorizationPolicy(authorization),
        idGenerator: SequentialCourierSettlementIdGenerator(),
        sessionRepository: sessionRepository,
        declarationRepository: declarationRepository,
        settlementRepository: settlementRepository,
        auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
        recordCashMovement: recordCashMovement,
      );
    }

    test(
        'approves, transitions the session, and records a matching '
        'CashMovement on the target drawer', () async {
      final useCase = buildUseCase(const AuthorizationResult(granted: true));

      final settlement = await useCase(
        settlementSessionId: 'csession-1',
        reviewedByStaffId: 'manager-1',
        targetCashSessionId: 'cash-session-1',
      );

      expect(settlement.status, CourierSettlementStatus.approved);

      final session = await sessionRepository.findById('csession-1');
      expect(session!.status, CourierSettlementSessionStatus.approved);

      final movements =
          await cashMovementRepository.findBySessionId('cash-session-1');
      expect(movements, hasLength(1));
      expect(movements.single.type, CashMovementType.courierCashSettlement);
      expect(movements.single.amount, Money.fromWhole(200, Currency.tryLira));
      expect(movements.single.settlementId, settlement.id);
    });

    test('throws when the reviewer is the declaring courier', () async {
      final useCase = buildUseCase(const AuthorizationResult(granted: true));

      expect(
        () => useCase(
          settlementSessionId: 'csession-1',
          reviewedByStaffId: 'courier-1',
          targetCashSessionId: 'cash-session-1',
        ),
        throwsA(isA<SelfApprovalNotAllowedViolation>()),
      );
    });

    test('throws when authorization is denied', () async {
      final useCase = buildUseCase(
        const AuthorizationResult(
            granted: false, reason: 'Yönetici değilsiniz'),
      );

      expect(
        () => useCase(
          settlementSessionId: 'csession-1',
          reviewedByStaffId: 'manager-1',
          targetCashSessionId: 'cash-session-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('throws when the session is not pendingApproval', () async {
      await sessionRepository.save(
        (await sessionRepository.findById('csession-1'))!.copyWith(
          status: CourierSettlementSessionStatus.active,
          revision: 2,
        ),
      );
      final useCase = buildUseCase(const AuthorizationResult(granted: true));

      expect(
        () => useCase(
          settlementSessionId: 'csession-1',
          reviewedByStaffId: 'manager-1',
          targetCashSessionId: 'cash-session-1',
        ),
        throwsA(isA<InvalidCourierSettlementSessionTransitionViolation>()),
      );
    });
  });
}
