import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_settlement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/reject_courier_settlement.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_declaration_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_cash_declaration.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_status.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_variance.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/courier_settlement_test_fixtures.dart';
import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  group('RejectCourierSettlement', () {
    late InMemoryCourierSettlementSessionRepository sessionRepository;
    late InMemoryCourierCashDeclarationRepository declarationRepository;
    late InMemoryCourierSettlementRepository settlementRepository;

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
        declaredAmount: Money.fromWhole(150, Currency.tryLira),
        variance: CourierSettlementVariance.compute(
          expectedAmount: Money.fromWhole(200, Currency.tryLira),
          declaredAmount: Money.fromWhole(150, Currency.tryLira),
        ),
        declaredAt: DateTime(2026, 7, 29, 22),
      ));
      settlementRepository = InMemoryCourierSettlementRepository();
    });

    RejectCourierSettlement buildUseCase(AuthorizationResult authorization) {
      return RejectCourierSettlement(
        clock: FakeClock(DateTime(2026, 7, 30, 9)),
        authorizationPolicy: FakePosAuthorizationPolicy(authorization),
        idGenerator: SequentialCourierSettlementIdGenerator(),
        sessionRepository: sessionRepository,
        declarationRepository: declarationRepository,
        settlementRepository: settlementRepository,
        auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
      );
    }

    test(
        'rejects and moves the session to rejected, recording no '
        'CashMovement', () async {
      final useCase = buildUseCase(const AuthorizationResult(granted: true));

      final settlement = await useCase(
        settlementSessionId: 'csession-1',
        reviewedByStaffId: 'manager-1',
        managerNotes: 'Tutar tutmuyor',
      );

      expect(settlement.status, CourierSettlementStatus.rejected);
      final session = await sessionRepository.findById('csession-1');
      expect(session!.status, CourierSettlementSessionStatus.rejected);
    });

    test('throws when the reviewer is the declaring courier', () async {
      final useCase = buildUseCase(const AuthorizationResult(granted: true));

      expect(
        () => useCase(
          settlementSessionId: 'csession-1',
          reviewedByStaffId: 'courier-1',
          managerNotes: 'x',
        ),
        throwsA(isA<SelfApprovalNotAllowedViolation>()),
      );
    });
  });
}
