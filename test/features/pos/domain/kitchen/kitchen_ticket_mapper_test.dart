import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_mapper.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faz R.1D.1 §15/§19 test 37 — KDS-compatibility check for the
/// `reservationPreorder` channel. `KitchenTicketMapper.fromOrder`'s own
/// `_channelLabel` switch already had a `reservationPreorder` case
/// (anticipated ahead of this phase — see the channel's own introduction);
/// this proves it actually works end-to-end against a real `Order`, not
/// just that the switch case exists.
///
/// Test 36 ("KDS does not expose a pendingConfirmation preorder") is not a
/// runtime test here: `FireKitchenTicket`/`KitchenTicketMapper` have no
/// Firestore query of their own and no status guard — they only ever map
/// whatever `Order` a caller explicitly hands them. No caller in this
/// codebase invokes them for a `reservationPreorder` order at all yet (no
/// scheduler exists — that's Faz R.1D.2's job), so there is no code path
/// today, for any channel, that could surface a `pendingConfirmation` order
/// on a kitchen ticket. This is a structural fact, verified by inspection
/// (`fire_kitchen_ticket.dart`, `kitchen_projection_repository.dart` — no
/// `orders` query, no status filter), not something a unit test can assert
/// as a negative.
Order _buildOrder({
  required OrderChannel channel,
  required OrderStatus status,
}) {
  final line = OrderLine.create(
    productId: 'p1',
    productName: 'Mexifit Bowl',
    quantity: 1,
    unitPrice: Money.fromWhole(194, Currency.tryLira),
    taxRate: TaxPolicy.defaultRate,
  );
  return Order(
    id: OrderId('order-preorder-1'),
    orderNumber: OrderNumber('RP-00000001'),
    status: status,
    channel: channel,
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
    customerId: 'customer-1',
    reservationContextId: 'reservation-1',
    lines: [line],
    pricing:
        PriceCalculator.calculate(lines: [line], currency: Currency.tryLira),
    timestamps: OrderTimestamps(created: DateTime(2026, 7, 28)),
  );
}

void main() {
  group('KitchenTicketMapper.fromOrder — reservationPreorder channel', () {
    test(
        'maps a confirmed reservationPreorder order without error, correct channel label',
        () {
      final order = _buildOrder(
        channel: OrderChannel.reservationPreorder,
        status: OrderStatus.confirmed,
      );

      final ticket = KitchenTicketMapper.fromOrder(
        ticketId: 'ticket-1',
        order: order,
        type: KitchenTicketType.initial,
        restaurantName: 'Test Restaurant',
        branchName: 'Merkez Şube',
        firedAt: DateTime(2026, 7, 28, 12, 0),
      );

      expect(ticket.header.channelLabel, 'Rezervasyon Ön Sipariş');
      expect(ticket.header.orderTypeLabel, 'Rezervasyon Ön Sipariş');
      expect(ticket.orderId, order.id);
      expect(ticket.lines, hasLength(1));
      expect(ticket.lines.single.productName, 'Mexifit Bowl');
    });
  });
}
