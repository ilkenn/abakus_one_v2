import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_order_view.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_station.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_work_item.dart';
import 'package:flutter_test/flutter_test.dart';

KitchenWorkItem _item({
  required String id,
  required KitchenLineStatus status,
  int quantity = 1,
  int readyQuantity = 0,
}) {
  return KitchenWorkItem(
    id: id,
    branchId: 'branch-1',
    station: KitchenStation.shared,
    orderId: OrderId('order-1'),
    kitchenTicketId: 'ticket-1',
    kitchenTicketLineId: id,
    quantity: quantity,
    readyQuantity: readyQuantity,
    status: status,
    queuedAt: DateTime(2026, 1, 1),
    revision: 1,
    idempotencyKey: 'ticket-1-$id',
  );
}

void main() {
  group('KitchenOrderView.build', () {
    test('is not fully ready while any line remains outstanding', () {
      final view = KitchenOrderView.build(
        orderId: OrderId('order-1'),
        kitchenTicketId: 'ticket-1',
        workItems: [
          _item(id: 'line-1', status: KitchenLineStatus.ready),
          _item(id: 'line-2', status: KitchenLineStatus.preparing),
        ],
      );

      expect(view.isFullyReady, isFalse);
    });

    test('is fully ready once every line reaches ready', () {
      final view = KitchenOrderView.build(
        orderId: OrderId('order-1'),
        kitchenTicketId: 'ticket-1',
        workItems: [
          _item(id: 'line-1', status: KitchenLineStatus.ready),
          _item(id: 'line-2', status: KitchenLineStatus.ready),
        ],
      );

      expect(view.isFullyReady, isTrue);
    });

    test('cancelled and unavailable lines never block order readiness', () {
      final view = KitchenOrderView.build(
        orderId: OrderId('order-1'),
        kitchenTicketId: 'ticket-1',
        workItems: [
          _item(id: 'line-1', status: KitchenLineStatus.ready),
          _item(id: 'line-2', status: KitchenLineStatus.cancelled),
          _item(id: 'line-3', status: KitchenLineStatus.unavailable),
        ],
      );

      expect(view.isFullyReady, isTrue);
    });

    test('an order with no work items is not fully ready', () {
      final view = KitchenOrderView.build(
        orderId: OrderId('order-1'),
        kitchenTicketId: 'ticket-1',
        workItems: const [],
      );

      expect(view.isFullyReady, isFalse);
    });

    test('line progress reports quantity-level completion', () {
      final view = KitchenOrderView.build(
        orderId: OrderId('order-1'),
        kitchenTicketId: 'ticket-1',
        workItems: [
          _item(
            id: 'line-1',
            status: KitchenLineStatus.preparing,
            quantity: 3,
            readyQuantity: 2,
          ),
        ],
      );

      expect(view.lines.single.isFullyReady, isFalse);
      expect(view.lines.single.readyQuantity, 2);
      expect(view.lines.single.quantity, 3);
    });
  });
}
