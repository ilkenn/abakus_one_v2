import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_cash_collection_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_cash_declaration_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_courier_cash_collection.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/submit_courier_cash_declaration.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_collection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_declaration_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/payment_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_collection_type.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_variance.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/courier_settlement_test_fixtures.dart';
import '../../test_support/fake_clock.dart';

void main() {
  group('SubmitCourierCashDeclaration', () {
    test(
        'expected amount sums every collection; session moves to '
        'pendingApproval', () async {
      final sessionRepository = InMemoryCourierSettlementSessionRepository();
      await sessionRepository.save(buildTestCourierSettlementSession());
      final paymentSessionRepository = InMemoryPaymentSessionRepository();
      await seedTestPaymentSession(repository: paymentSessionRepository);
      final collectionRepository = InMemoryCourierCashCollectionRepository();
      final recordCollection = RecordCourierCashCollection(
        clock: FakeClock(DateTime(2026, 7, 29, 12)),
        idGenerator: SequentialCourierCashCollectionIdGenerator(),
        sessionRepository: sessionRepository,
        paymentSessionRepository: paymentSessionRepository,
        collectionRepository: collectionRepository,
        auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
      );
      await recordCollection(
        settlementSessionId: 'csession-1',
        orderId: OrderId('order-1'),
        paymentSessionId: 'ps-1',
        collectedAmount: Money.fromWhole(60, Currency.tryLira),
        collectionType: CourierCollectionType.full,
      );
      await recordCollection(
        settlementSessionId: 'csession-1',
        orderId: OrderId('order-1'),
        paymentSessionId: 'ps-1',
        collectedAmount: Money.fromWhole(40, Currency.tryLira),
        collectionType: CourierCollectionType.full,
      );

      final declarationRepository = InMemoryCourierCashDeclarationRepository();
      final declaration = await SubmitCourierCashDeclaration(
        clock: FakeClock(DateTime(2026, 7, 29, 22)),
        idGenerator: SequentialCourierCashDeclarationIdGenerator(),
        sessionRepository: sessionRepository,
        collectionRepository: collectionRepository,
        declarationRepository: declarationRepository,
        auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
      )(
          settlementSessionId: 'csession-1',
          declaredAmount: Money.fromWhole(100, Currency.tryLira));

      expect(
          declaration.expectedAmount, Money.fromWhole(100, Currency.tryLira));
      expect(declaration.variance.type, CourierVarianceType.exact);

      final session = await sessionRepository.findById('csession-1');
      expect(session!.status, CourierSettlementSessionStatus.pendingApproval);
    });

    test('a redeclaration after rejection is a brand-new record', () async {
      final sessionRepository = InMemoryCourierSettlementSessionRepository();
      await sessionRepository.save(buildTestCourierSettlementSession(
        status: CourierSettlementSessionStatus.rejected,
      ));
      final declarationRepository = InMemoryCourierCashDeclarationRepository();

      final declaration = await submitTestCourierCashDeclaration(
        sessionRepository: sessionRepository,
        collectionRepository: InMemoryCourierCashCollectionRepository(),
        declarationRepository: declarationRepository,
        settlementSessionId: 'csession-1',
        declaredAmount: Money.fromWhole(50, Currency.tryLira),
      );

      expect(declaration.declaredAmount, Money.fromWhole(50, Currency.tryLira));
      final session = await sessionRepository.findById('csession-1');
      expect(session!.status, CourierSettlementSessionStatus.pendingApproval);
    });
  });
}
