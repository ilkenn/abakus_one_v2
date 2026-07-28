import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/payment_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

PaymentSession _session({
  String id = 'ps1',
  String orderId = 'order-1',
  PaymentSessionStatus status = PaymentSessionStatus.collecting,
  int revision = 1,
  DateTime? createdAt,
}) {
  return PaymentSession(
    id: id,
    orderId: OrderId(orderId),
    totalAmount: Money.fromWhole(100, Currency.tryLira),
    status: status,
    createdAt: createdAt ?? DateTime(2026, 7, 28),
    revision: revision,
  );
}

void main() {
  group('InMemoryPaymentSessionRepository — append-only', () {
    test('save never overwrites a previous revision', () async {
      final repository = InMemoryPaymentSessionRepository();
      await repository.save(_session(revision: 1));
      await repository.save(_session(revision: 2));

      expect(repository.allRevisions, hasLength(2));
    });

    test('findBySessionId returns the highest-revision entry', () async {
      final repository = InMemoryPaymentSessionRepository();
      await repository.save(_session(revision: 1, status: PaymentSessionStatus.collecting));
      await repository.save(_session(revision: 2, status: PaymentSessionStatus.completed));

      final found = await repository.findBySessionId('ps1');

      expect(found!.revision, 2);
      expect(found.status, PaymentSessionStatus.completed);
    });

    test('findBySessionId returns null when nothing was saved', () async {
      final repository = InMemoryPaymentSessionRepository();
      expect(await repository.findBySessionId('nonexistent'), isNull);
    });
  });

  group('InMemoryPaymentSessionRepository — findActiveByOrderId', () {
    test('returns the latest revision when the most recent session is non-terminal', () async {
      final repository = InMemoryPaymentSessionRepository();
      await repository.save(_session(status: PaymentSessionStatus.collecting));

      final active = await repository.findActiveByOrderId(OrderId('order-1'));

      expect(active, isNotNull);
      expect(active!.status, PaymentSessionStatus.collecting);
    });

    test('returns null when the most recently started session is completed', () async {
      final repository = InMemoryPaymentSessionRepository();
      await repository.save(_session(status: PaymentSessionStatus.completed));

      final active = await repository.findActiveByOrderId(OrderId('order-1'));

      expect(active, isNull);
    });

    test('returns null when the most recently started session is cancelled', () async {
      final repository = InMemoryPaymentSessionRepository();
      await repository.save(_session(status: PaymentSessionStatus.cancelled));

      final active = await repository.findActiveByOrderId(OrderId('order-1'));

      expect(active, isNull);
    });

    test('a later, freshly-started session becomes active even if an earlier one for the same order was cancelled', () async {
      final repository = InMemoryPaymentSessionRepository();
      await repository.save(_session(
        id: 'ps1',
        status: PaymentSessionStatus.cancelled,
        createdAt: DateTime(2026, 7, 28, 10, 0),
      ));
      await repository.save(_session(
        id: 'ps2',
        status: PaymentSessionStatus.collecting,
        createdAt: DateTime(2026, 7, 28, 11, 0),
      ));

      final active = await repository.findActiveByOrderId(OrderId('order-1'));

      expect(active!.id, 'ps2');
    });

    test('returns null for an order with no session at all', () async {
      final repository = InMemoryPaymentSessionRepository();
      expect(await repository.findActiveByOrderId(OrderId('unknown')), isNull);
    });
  });

  group('InMemoryPaymentSessionRepository — findHistoryByOrderId', () {
    test('returns every revision across every session for the order, oldest first', () async {
      final repository = InMemoryPaymentSessionRepository();
      await repository.save(_session(
        id: 'ps1',
        revision: 1,
        createdAt: DateTime(2026, 7, 28, 10, 0),
      ));
      await repository.save(_session(
        id: 'ps1',
        revision: 2,
        status: PaymentSessionStatus.cancelled,
        createdAt: DateTime(2026, 7, 28, 10, 0),
      ));
      await repository.save(_session(
        id: 'ps2',
        revision: 1,
        createdAt: DateTime(2026, 7, 28, 11, 0),
      ));

      final history = await repository.findHistoryByOrderId(OrderId('order-1'));

      expect(history, hasLength(3));
      expect(history.first.id, 'ps1');
      expect(history.last.id, 'ps2');
    });

    test('history is empty for an order with no sessions', () async {
      final repository = InMemoryPaymentSessionRepository();
      final history = await repository.findHistoryByOrderId(OrderId('unknown'));
      expect(history, isEmpty);
    });
  });

  group('InMemoryPaymentSessionRepository — failure injection', () {
    test('failOnSave throws once, then clears itself', () async {
      final repository = InMemoryPaymentSessionRepository();
      repository.failOnSave = Exception('disk full');

      await expectLater(repository.save(_session()), throwsException);
      await expectLater(repository.save(_session()), completes);
    });
  });
}
