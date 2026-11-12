import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_line.dart';
import '../../../orders/domain/models/order_line_modifier_selection.dart';
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
      // Self-Order QR Faz 5 — `lineApprovalStates` is index-paired with
      // `lines` (see that class's own doc comment); a channel without the
      // concept at all (every non-dine-in order) has an empty list here,
      // so this always falls back to `null` for them.
      final approvalState = order.lineApprovalStates
          .where((state) => state.lineIndex == i)
          .firstOrNull;
      lines.add(KitchenTicketLine(
        id: '$ticketId-line-$i',
        productName: orderLine.productName,
        quantity: orderLine.quantity,
        ingredientSummary: _ingredientSummaryFor(orderLine),
        // 2026-11-11 — the note staff type on a line is stored server-side
        // as the line's `customerNote` (`buildProductLine`), which the
        // kitchen never saw; both notes now reach the ticket and the KDS.
        note: [orderLine.kitchenNote, orderLine.customerNote]
            .where((note) => note.trim().isNotEmpty)
            .join(' · '),
        orderedByName: approvalState?.orderedByName,
        weightGrams: orderLine.weightGrams,
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
        tableLabel: order.tableId == null ? null : 'Masa ${order.tableId}',
        customerName: _customerName(order),
        channel: order.channel,
        orderStatus: order.status,
        orderNote: order.kitchenNote.trim(),
      ),
      lines: lines,
      isCopy: isCopy,
      firedAt: firedAt,
      revision: 1,
    );
  }

  /// Groups [orderLine.modifiers] by `groupName` (e.g. "Karbonhidrat:
  /// Meksika Pilavı (+20 TL)", "Ekstra: Cheddar Peyniri (+60 TL), Abaküs
  /// Sos (+25 TL)"), then appends a trailing "ÇIKAR: ..." line for
  /// [OrderLine.excludedIngredients] — the exact hierarchy the 2026-10-30
  /// product-configurator spec requires. Preserves each group's
  /// first-seen order rather than alphabetizing, so "Karbonhidrat" prints
  /// before "Salata" when the customer selected them in that order (every
  /// real call site selects groups in the catalog's own declared order).
  static List<String> _ingredientSummaryFor(OrderLine orderLine) {
    final order = <String>[];
    final byGroup = <String, List<String>>{};
    for (final modifier in orderLine.modifiers) {
      byGroup.putIfAbsent(modifier.groupName, () {
        order.add(modifier.groupName);
        return <String>[];
      }).add(_modifierDisplay(modifier));
    }
    final result = [
      for (final groupName in order)
        '$groupName: ${byGroup[groupName]!.join(", ")}',
    ];
    if (orderLine.excludedIngredients.isNotEmpty) {
      result.add('ÇIKAR: ${orderLine.excludedIngredients.join(", ")}');
    }
    return result;
  }

  static String _modifierDisplay(OrderLineModifierSelection modifier) {
    final qtyLabel = modifier.quantity > 1
        ? '${modifier.optionName} x${modifier.quantity}'
        : modifier.optionName;
    if (modifier.totalExtraPrice.isZero) return qtyLabel;
    final wholeTl = modifier.totalExtraPrice.minorUnits ~/
        modifier.totalExtraPrice.currency.minorUnitsPerWhole;
    return '$qtyLabel (+$wholeTl TL)';
  }

  /// `null` when the order carries no contact name at all — never an empty
  /// string, so callers can treat "no customer name" as a single `null`
  /// check rather than also trimming/blank-checking.
  static String? _customerName(Order order) {
    final first = order.contactFirstName?.trim() ?? '';
    final last = order.contactLastName?.trim() ?? '';
    final full = [first, last].where((part) => part.isNotEmpty).join(' ');
    return full.isEmpty ? null : full;
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
