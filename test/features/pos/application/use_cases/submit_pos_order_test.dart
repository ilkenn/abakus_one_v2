import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/discounts/discount.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/submit_pos_order.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

void main() {
  group('SubmitPosOrder — happy path', () {
    test('produces an Order at pendingConfirmation, via the required created -> pendingConfirmation transition', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final repository = InMemoryPosOrderRepository();
      final identityProvider = InMemoryOrderIdentityProvider();
      final session = buildTestSession(sessionId: 'session-1', openedAt: clock.now())
          .copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );

      final order = await SubmitPosOrder(
        clock: clock,
        identityProvider: identityProvider,
        repository: repository,
        restaurantId: 'restaurant-abakus',
      ).call(session);

      expect(order.status, OrderStatus.pendingConfirmation);
      expect(order.branchId, session.branchId);
      expect(order.restaurantId, 'restaurant-abakus');
      expect(order.channel, session.channel);
    });

    test('appends exactly one OrderAuditEntry recording created -> pendingConfirmation, actor staff', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );

      final order = await SubmitPosOrder(
        clock: clock,
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryPosOrderRepository(),
        restaurantId: 'restaurant-abakus',
      ).call(session);

      expect(order.statusHistory, hasLength(1));
      final entry = order.statusHistory.single;
      expect(entry.previousValue, 'created');
      expect(entry.newValue, 'pendingConfirmation');
      expect(entry.actor, OrderActor.staff);
    });

    test('never skips directly from created to confirmed', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );

      final order = await SubmitPosOrder(
        clock: clock,
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryPosOrderRepository(),
        restaurantId: 'restaurant-abakus',
      ).call(session);

      expect(order.status, isNot(OrderStatus.confirmed));
      expect(order.version, 2); // created (v1) -> pendingConfirmation (v2)
    });

    test('obtains identity through OrderIdentityProvider, never inventing one', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final identityProvider = InMemoryOrderIdentityProvider(prefix: 'test');
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );

      final order = await SubmitPosOrder(
        clock: clock,
        identityProvider: identityProvider,
        repository: InMemoryPosOrderRepository(),
        restaurantId: 'restaurant-abakus',
      ).call(session);

      expect(order.id.value, startsWith('test-order-'));
      expect(order.orderNumber.value, startsWith('test-'));
    });

    test('snapshots order-level customerNote/kitchenNote from the session', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        customerNote: 'Zile basmayın',
        kitchenNote: 'Acil',
      );

      final order = await SubmitPosOrder(
        clock: clock,
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryPosOrderRepository(),
        restaurantId: 'restaurant-abakus',
      ).call(session);

      expect(order.customerNote, 'Zile basmayın');
      expect(order.kitchenNote, 'Acil');
    });

    test('applies the session discount to the resulting PriceBreakdown', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        discount: Discount.fixedAmount(
          id: 'd1',
          scope: DiscountScope.order,
          amount: Money.fromWhole(10, Currency.tryLira),
        ),
      );

      final order = await SubmitPosOrder(
        clock: clock,
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryPosOrderRepository(),
        restaurantId: 'restaurant-abakus',
      ).call(session);

      expect(order.pricing.discount, Money.fromWhole(10, Currency.tryLira));
      expect(order.pricing.grandTotal, Money.fromWhole(90, Currency.tryLira));
    });

    test('persists via PosOrderRepository.submitOrder', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final repository = InMemoryPosOrderRepository();
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );

      final order = await SubmitPosOrder(
        clock: clock,
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: repository,
        restaurantId: 'restaurant-abakus',
      ).call(session);

      expect(repository.submittedOrders.map((o) => o.id), contains(order.id));
    });

    test('deletes the draft only after a successful submission', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final repository = InMemoryPosOrderRepository();
      final session = buildTestSession(sessionId: 'session-1', openedAt: clock.now())
          .copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );
      await repository.saveDraft('session-1', session);

      await SubmitPosOrder(
        clock: clock,
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: repository,
        restaurantId: 'restaurant-abakus',
      ).call(session);

      expect(repository.draftIds, isNot(contains('session-1')));
    });
  });

  group('SubmitPosOrder — validation and failure', () {
    test('rejects an empty session', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      expect(
        () => SubmitPosOrder(
          clock: clock,
          identityProvider: InMemoryOrderIdentityProvider(),
          repository: InMemoryPosOrderRepository(),
          restaurantId: 'restaurant-abakus',
        ).call(session),
        throwsA(isA<EmptyOrderViolation>()),
      );
    });

    test('does not delete the draft when the repository submit step fails', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final repository = InMemoryPosOrderRepository();
      final session = buildTestSession(sessionId: 'session-1', openedAt: clock.now())
          .copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );
      await repository.saveDraft('session-1', session);
      repository.failOnSubmitOrder = Exception('backend unavailable');

      await expectLater(
        SubmitPosOrder(
          clock: clock,
          identityProvider: InMemoryOrderIdentityProvider(),
          repository: repository,
          restaurantId: 'restaurant-abakus',
        ).call(session),
        throwsException,
      );

      expect(repository.draftIds, contains('session-1'));
    });

    test('a retry after a failed submission succeeds (one-shot failure injection)', () async {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final repository = InMemoryPosOrderRepository();
      final session = buildTestSession(sessionId: 'session-1', openedAt: clock.now())
          .copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );
      await repository.saveDraft('session-1', session);
      repository.failOnSubmitOrder = Exception('backend unavailable');
      final useCase = SubmitPosOrder(
        clock: clock,
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: repository,
        restaurantId: 'restaurant-abakus',
      );

      await expectLater(useCase.call(session), throwsException);
      final order = await useCase.call(session);

      expect(order.status, OrderStatus.pendingConfirmation);
      expect(repository.draftIds, isNot(contains('session-1')));
    });
  });
}
