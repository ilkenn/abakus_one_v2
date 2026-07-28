import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_mapper.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'builds a ticket with full ingredient snapshot per line, even for a ready-made product',
      () {
    final order = CartToOrderMapper.map(
      orderId: OrderId('order-1'),
      orderNumber: OrderNumber('A-001'),
      cartItems: const [
        CartItem(
          id: 'p1',
          name: 'Mexifit Bowl',
          desc: '',
          price: 194.0,
          quantity: 2,
          note: 'az baharatlı',
        ),
      ],
      channel: OrderChannel.dineInStaff,
      branchId: 'branch-1',
      restaurantId: 'restaurant-abakus',
      now: DateTime(2026, 7, 29),
    );

    final ticket = KitchenTicketMapper.fromOrder(
      ticketId: 'ticket-1',
      order: order,
      type: KitchenTicketType.initial,
      restaurantName: 'Abaküs',
      branchName: 'Kadıköy',
      firedAt: DateTime(2026, 7, 29, 12),
    );

    expect(ticket.header.orderNumber, 'A-001');
    expect(ticket.header.channelLabel, 'Masa');
    expect(ticket.lines, hasLength(1));
    expect(ticket.lines.first.productName, 'Mexifit Bowl');
    expect(ticket.lines.first.quantity, 2);
    expect(ticket.isCopy, isFalse);
    expect(ticket.revision, 1);
  });
}
