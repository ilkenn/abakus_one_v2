/// The header block every printed/digital [KitchenTicket] must show.
class KitchenTicketHeader {
  const KitchenTicketHeader({
    required this.restaurantName,
    required this.branchName,
    required this.channelLabel,
    required this.orderNumber,
    required this.orderTypeLabel,
    required this.receivedAt,
    this.priority = '',
    this.tableLabel,
    this.customerName,
  });

  final String restaurantName;
  final String branchName;

  /// Source platform/channel, human-readable (e.g. "Masa QR", "Gel-Al",
  /// "Getir Yemek") — display text, not the raw `OrderChannel` enum name.
  final String channelLabel;

  final String orderNumber;

  /// Dine-in / takeaway / delivery / reservation — display text.
  final String orderTypeLabel;

  final DateTime receivedAt;

  /// Free-text priority marker (e.g. "ACİL") — empty for normal priority,
  /// not modeled as an enum since kitchens define their own urgency
  /// vocabulary.
  final String priority;

  /// AP-5 Sprint 4 — display-only table reference (e.g. "Masa 5"), derived
  /// from `Order.tableId`. `null` for channels with no table (takeaway/
  /// delivery/reservation-preorder). Additive beyond BR-KITCHEN-006's
  /// locked required-field list (which names a floor, not a ceiling) —
  /// never removes/replaces any of that rule's own required fields.
  final String? tableLabel;

  /// AP-5 Sprint 4 — display-only customer name, derived from
  /// `Order.contactFirstName`/`contactLastName`. `null` when the order
  /// carries no contact name. Same additive-beyond-BR-KITCHEN-006 note as
  /// [tableLabel].
  final String? customerName;
}
