import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_cash_declaration_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/start_payment_session.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/submit_courier_cash_declaration.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_collection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_declaration_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/payment_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_cash_declaration.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';

import 'fake_clock.dart';

/// A minimal, valid, active [CourierSettlementSession] for use-case tests
/// that need a starting point rather than exercising
/// `OpenCourierSettlementSession` itself.
CourierSettlementSession buildTestCourierSettlementSession({
  String sessionId = 'csession-1',
  String courierId = 'courier-1',
  CourierSettlementSessionStatus status = CourierSettlementSessionStatus.active,
  int revision = 1,
}) {
  return CourierSettlementSession(
    id: sessionId,
    courierId: courierId,
    branchId: 'branch-1',
    status: status,
    openedAt: DateTime(2026, 7, 29, 9),
    revision: revision,
  );
}

/// A real, saved [PaymentSession] for a test order — `RecordCourierCashCollection`
/// validates against a real `PaymentSessionRepository`, so tests need an
/// actual session on record, not a fabricated id.
Future<PaymentSession> seedTestPaymentSession({
  required PaymentSessionRepository repository,
  String paymentSessionId = 'ps-1',
  String orderId = 'order-1',
  Money? totalAmount,
}) async {
  final session =
      StartPaymentSession(clock: FakeClock(DateTime(2026, 7, 29, 8))).call(
    sessionId: paymentSessionId,
    orderId: OrderId(orderId),
    totalAmount: totalAmount ?? Money.fromWhole(100, Currency.tryLira),
  );
  await repository.save(session);
  return session;
}

/// Seeds a `session` (active) with a single submitted
/// [CourierCashDeclaration] via the real `SubmitCourierCashDeclaration`
/// use case — used by `ApproveCourierSettlement`/`RejectCourierSettlement`/
/// `CloseCourierSettlementSession` tests that need a session already
/// sitting at `pendingApproval`.
Future<CourierCashDeclaration> submitTestCourierCashDeclaration({
  required CourierSettlementSessionRepository sessionRepository,
  required CourierCashCollectionRepository collectionRepository,
  required CourierCashDeclarationRepository declarationRepository,
  required String settlementSessionId,
  required Money declaredAmount,
}) {
  return SubmitCourierCashDeclaration(
    clock: FakeClock(DateTime(2026, 7, 29, 22)),
    idGenerator: SequentialCourierCashDeclarationIdGenerator(),
    sessionRepository: sessionRepository,
    collectionRepository: collectionRepository,
    declarationRepository: declarationRepository,
    auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
  )(
    settlementSessionId: settlementSessionId,
    declaredAmount: declaredAmount,
  );
}
