import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_cash_collection_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_courier_cash_collection.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_collection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/payment_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_collection_type.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/courier_settlement_test_fixtures.dart';
import '../../test_support/fake_clock.dart';

void main() {
  group('RecordCourierCashCollection', () {
    late InMemoryCourierSettlementSessionRepository sessionRepository;
    late InMemoryPaymentSessionRepository paymentSessionRepository;
    late InMemoryCourierCashCollectionRepository collectionRepository;
    late RecordCourierCashCollection useCase;

    setUp(() async {
      sessionRepository = InMemoryCourierSettlementSessionRepository();
      await sessionRepository.save(buildTestCourierSettlementSession());
      paymentSessionRepository = InMemoryPaymentSessionRepository();
      collectionRepository = InMemoryCourierCashCollectionRepository();
      useCase = RecordCourierCashCollection(
        clock: FakeClock(DateTime(2026, 7, 29, 12)),
        idGenerator: SequentialCourierCashCollectionIdGenerator(),
        sessionRepository: sessionRepository,
        paymentSessionRepository: paymentSessionRepository,
        collectionRepository: collectionRepository,
        auditRepository: InMemoryCourierSettlementAuditEntryRepository(),
      );
    });

    test('records a full collection referencing a real PaymentSession',
        () async {
      await seedTestPaymentSession(repository: paymentSessionRepository);

      final collection = await useCase(
        settlementSessionId: 'csession-1',
        orderId: OrderId('order-1'),
        paymentSessionId: 'ps-1',
        collectedAmount: Money.fromWhole(100, Currency.tryLira),
        collectionType: CourierCollectionType.full,
      );

      expect(collection.collectionType, CourierCollectionType.full);
      final stored =
          await collectionRepository.findBySettlementSessionId('csession-1');
      expect(stored, hasLength(1));
    });

    test('throws when the referenced PaymentSession does not exist', () async {
      expect(
        () => useCase(
          settlementSessionId: 'csession-1',
          orderId: OrderId('order-1'),
          paymentSessionId: 'unknown-ps',
          collectedAmount: Money.fromWhole(100, Currency.tryLira),
          collectionType: CourierCollectionType.full,
        ),
        throwsA(isA<UnknownCourierSettlementEntityViolation>()),
      );
    });

    test('allows a zero-amount failed collection', () async {
      await seedTestPaymentSession(repository: paymentSessionRepository);

      final collection = await useCase(
        settlementSessionId: 'csession-1',
        orderId: OrderId('order-1'),
        paymentSessionId: 'ps-1',
        collectedAmount: Money.zero(Currency.tryLira),
        collectionType: CourierCollectionType.failed,
      );

      expect(collection.collectedAmount.isZero, isTrue);
    });
  });
}
