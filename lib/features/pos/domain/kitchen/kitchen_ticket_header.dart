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
}
