import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/pos_test_fixtures.dart';

void main() {
  group('InMemoryPosOrderRepository — draft contract', () {
    test('getDraft returns null when nothing was saved', () async {
      final repository = InMemoryPosOrderRepository();
      expect(await repository.getDraft('nonexistent'), isNull);
    });

    test('saveDraft then getDraft returns the same session', () async {
      final repository = InMemoryPosOrderRepository();
      final session = buildTestSession(sessionId: 'session-1');

      await repository.saveDraft('session-1', session);
      final loaded = await repository.getDraft('session-1');

      expect(loaded, isNotNull);
      expect(loaded!.sessionId, 'session-1');
    });

    test('saveDraft overwrites a previous draft under the same key', () async {
      final repository = InMemoryPosOrderRepository();
      final first = buildTestSession(sessionId: 'session-1');
      final second = first.copyWith(customerNote: 'updated');

      await repository.saveDraft('session-1', first);
      await repository.saveDraft('session-1', second);
      final loaded = await repository.getDraft('session-1');

      expect(loaded!.customerNote, 'updated');
    });

    test('deleteDraft removes the stored draft', () async {
      final repository = InMemoryPosOrderRepository();
      await repository.saveDraft(
          'session-1', buildTestSession(sessionId: 'session-1'));

      await repository.deleteDraft('session-1');

      expect(await repository.getDraft('session-1'), isNull);
    });

    test('does not generate a draftId itself — the caller supplies it entirely',
        () async {
      final repository = InMemoryPosOrderRepository();
      await repository.saveDraft('caller-chosen-id', buildTestSession());

      expect(repository.draftIds, ['caller-chosen-id']);
    });
  });

  group('InMemoryPosOrderRepository — submitOrder', () {
    test('persists and returns the given order unchanged', () async {
      final repository = InMemoryPosOrderRepository();
      final order = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        channel: OrderChannel.dineInStaff,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 29),
      );

      final result = await repository.submitOrder(order);

      expect(result.id, order.id);
      expect(repository.submittedOrders, contains(order));
    });
  });

  group('InMemoryPosOrderRepository — failure injection', () {
    test('failOnSaveDraft throws once, then clears itself', () async {
      final repository = InMemoryPosOrderRepository();
      repository.failOnSaveDraft = Exception('disk full');

      await expectLater(
        repository.saveDraft('session-1', buildTestSession()),
        throwsException,
      );
      await expectLater(
        repository.saveDraft('session-1', buildTestSession()),
        completes,
      );
    });

    test('failOnGetDraft throws once, then clears itself', () async {
      final repository = InMemoryPosOrderRepository();
      repository.failOnGetDraft = Exception('read error');

      await expectLater(repository.getDraft('session-1'), throwsException);
      await expectLater(repository.getDraft('session-1'), completes);
    });

    test('failOnDeleteDraft throws once, then clears itself', () async {
      final repository = InMemoryPosOrderRepository();
      repository.failOnDeleteDraft = Exception('write error');

      await expectLater(repository.deleteDraft('session-1'), throwsException);
      await expectLater(repository.deleteDraft('session-1'), completes);
    });

    test('failOnSubmitOrder throws once, then clears itself', () async {
      final repository = InMemoryPosOrderRepository();
      repository.failOnSubmitOrder = Exception('backend unavailable');
      final order = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        channel: OrderChannel.dineInStaff,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 29),
      );

      await expectLater(repository.submitOrder(order), throwsException);
      await expectLater(repository.submitOrder(order), completes);
    });
  });
}
