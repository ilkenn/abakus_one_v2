import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_channel.dart';
import 'kitchen_ticket.dart';
import 'kitchen_ticket_header.dart';
import 'kitchen_ticket_line.dart';
import 'kitchen_ticket_type.dart';

/// Builds a [KitchenTicket] from an [Order] — the same "snapshot at fire
/// time" principle `CartToOrderMapper` already follows for orders
/// themselves.
abstract final class KitchenTicketMapper {
  KitchenTicketMapper._();

  /// [ticketId] is externally supplied (`KitchenTicketIdGenerator`). Each
  /// [KitchenTicketLine.id] is deterministically derived from it
  /// (`'<ticketId>-line-<index>'`) — never a timestamp/random value,
  /// matching this codebase's identity conventions.
  static KitchenTicket fromOrder({
    required String ticketId,
    required Order order,
    required KitchenTicketType type,
    required String restaurantName,
    required String branchName,
    required DateTime firedAt,
    bool isCopy = false,
    String priority = '',
  }) {
    final lines = <KitchenTicketLine>[];
    for (var i = 0; i < order.lines.length; i++) {
      final orderLine = order.lines[i];
      lines.add(KitchenTicketLine(
        id: '$ticketId-line-$i',
        productName: orderLine.productName,
        quantity: orderLine.quantity,
        ingredientSummary: [
          for (final modifier in orderLine.modifiers)
            modifier.quantity > 1
                ? '${modifier.optionName} x${modifier.quantity}'
                : modifier.optionName,
        ],
        note: orderLine.kitchenNote,
      ));
    }

    return KitchenTicket(
      id: ticketId,
      orderId: order.id,
      branchId: order.branchId,
      type: type,
      header: KitchenTicketHeader(
        restaurantName: restaurantName,
        branchName: branchName,
        channelLabel: _channelLabel(order.channel),
        orderNumber: order.orderNumber.value,
        orderTypeLabel: _channelLabel(order.channel),
        receivedAt: firedAt,
        priority: priority,
      ),
      lines: lines,
      isCopy: isCopy,
      firedAt: firedAt,
      revision: 1,
    );
  }

  static String _channelLabel(OrderChannel channel) {
    switch (channel) {
      case OrderChannel.dineInQr:
        return 'Masa (QR)';
      case OrderChannel.dineInStaff:
        return 'Masa';
      case OrderChannel.takeaway:
        return 'Gel-Al';
      case OrderChannel.delivery:
        return 'Teslimat';
      case OrderChannel.reservationPreorder:
        return 'Rezervasyon Ön Sipariş';
    }
  }
}
