import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_cash_collection_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_cash_declaration_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_settlement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_settlement_session_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/approve_courier_settlement.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/open_courier_settlement_session.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_cash_movement.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_courier_cash_collection.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/submit_courier_cash_declaration.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_collection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_declaration_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/payment_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement_type.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_collection_type.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/cash_test_fixtures.dart';
import '../test_support/courier_settlement_test_fixtures.dart';
import '../test_support/fake_clock.dart';
import '../test_support/fake_pos_authorization_policy.dart';

/// End-to-end: a real `PaymentSession` (Sprint 3C) is collected in cash by
/// a courier (Sprint 3F), declared, manager-approved, and the approval
/// automatically lands a `CashMovement` on a real `CashSession` drawer
/// (Sprint 3E) — with a traceable link back to the settlement that caused
/// it, and without ever touching the `PaymentSession` itself.
void main() {
  test(
      'Payment -> Courier Cash Collection -> Declaration -> Approval -> '
      'CashMovement, end to end', () async {
    // --- Sprint 3C: an order's payment was already collected in cash by
    // the courier at the door (recorded as a normal completed PaymentSession
    // — this test only needs it to exist, not to re-collect it). ---
    final paymentSessionRepository = InMemoryPaymentSessionRepository();
    await seedTestPaymentSession(
      repository: paymentSessionRepository,
      paymentSessionId: 'ps-delivery-1',
      orderId: 'order-delivery-1',
      totalAmount: Money.fromWhole(180, Currency.tryLira),
    );

    // --- Sprint 3F Phase 3: courier shift starts. ---
    final settlementSessionRepository =
        InMemoryCourierSettlementSessionRepository();
    final openSession = OpenCourierSettlementSession(
      clock: FakeClock(DateTime(2026, 7, 30, 8)),
      idGenerator: SequentialCourierSettlementSessionIdGenerator(),
      sessionRepository: settlementSessionRepository,
    );
    final settlementSession =
        await openSession(courierId: 'courier-9', branchId: 'branch-1');

    // --- Phase 2: cash collected at the door, referencing the real
    // PaymentSession and order. ---
    final collectionRepository = InMemoryCourierCashCollectionRepository();
    final recordCollection = RecordCourierCashCollection(
      clock: FakeClock(DateTime(2026, 7, 30, 12)),
      idGenerator: SequentialCourierCashCollectionIdGenerator(),
      sessionRepository: settlementSessionRepository,
      paymentSessionRepository: paymentSessionRepository,
      collectionRepository: collectionRepository,
      auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
    );
    await recordCollection(
      settlementSessionId: settlementSession.id,
      orderId: OrderId('order-delivery-1'),
      paymentSessionId: 'ps-delivery-1',
      collectedAmount: Money.fromWhole(180, Currency.tryLira),
      collectionType: CourierCollectionType.full,
    );

    // PaymentSession itself is untouched by any of the above.
    final unchangedPaymentSession =
        await paymentSessionRepository.findBySessionId('ps-delivery-1');
    expect(unchangedPaymentSession!.revision, 1);

    // --- Phase 3/4: end of shift, courier declares total cash on hand. ---
    final declarationRepository = InMemoryCourierCashDeclarationRepository();
    final declaration = await SubmitCourierCashDeclaration(
      clock: FakeClock(DateTime(2026, 7, 30, 20)),
      idGenerator: SequentialCourierCashDeclarationIdGenerator(),
      sessionRepository: settlementSessionRepository,
      collectionRepository: collectionRepository,
      declarationRepository: declarationRepository,
      auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
    )(
      settlementSessionId: settlementSession.id,
      declaredAmount: Money.fromWhole(180, Currency.tryLira),
    );
    expect(declaration.variance.isExact, isTrue);

    // --- Sprint 3E: the branch already has an open drawer session the
    // courier will hand cash into. ---
    final cashSessionRepository = InMemoryCashSessionRepository();
    await cashSessionRepository
        .save(buildTestCashSession(sessionId: 'drawer-session-1'));
    final cashMovementRepository = InMemoryCashMovementRepository();
    final recordCashMovement = RecordCashMovement(
      clock: FakeClock(DateTime(2026, 7, 30, 21)),
      idGenerator: SequentialCashMovementIdGenerator(),
      sessionRepository: cashSessionRepository,
      movementRepository: cashMovementRepository,
      auditRepository: InMemoryCashAuditEntryRepository(),
    );

    // --- Phase 3/5: manager approves; approval automatically records the
    // CashMovement on the target drawer. ---
    final settlementRepository = InMemoryCourierSettlementRepository();
    final approve = ApproveCourierSettlement(
      clock: FakeClock(DateTime(2026, 7, 30, 21)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      idGenerator: SequentialCourierSettlementIdGenerator(),
      sessionRepository: settlementSessionRepository,
      declarationRepository: declarationRepository,
      settlementRepository: settlementRepository,
      auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
      recordCashMovement: recordCashMovement,
    );
    final settlement = await approve(
      settlementSessionId: settlementSession.id,
      reviewedByStaffId: 'manager-1',
      targetCashSessionId: 'drawer-session-1',
    );

    // --- Verify the whole chain landed correctly, with no duplication. ---
    final movements =
        await cashMovementRepository.findBySessionId('drawer-session-1');
    expect(movements, hasLength(1));
    expect(movements.single.type, CashMovementType.courierCashSettlement);
    expect(movements.single.amount, Money.fromWhole(180, Currency.tryLira));
    expect(movements.single.settlementId, settlement.id);

    final paymentSessionAfterApproval =
        await paymentSessionRepository.findBySessionId('ps-delivery-1');
    expect(paymentSessionAfterApproval!.revision, 1,
        reason: 'the original PaymentSession is never modified or '
            'duplicated by the courier-settlement flow');
  });
}
