/// One line item on a printed "ara hesap fişi" (interim till receipt),
/// 2026-11-05 — real ESC/POS printing feature. [recipeSummary] is the
/// product's own standard recipe text (`MenuProduct.description`, the same
/// source the menu-PDF ingredient list already comes from), always printed
/// so kitchen/front-of-house staff see exactly what the dish normally
/// contains. [selectionNotes] carries the order-specific deviations from
/// that standard — grouped modifier selections, excluded ingredients, and
/// any free-text kitchen note — mirroring `KitchenTicketMapper`'s own
/// grouping so the printed receipt and the kitchen ticket never disagree.
class ReceiptLineItem {
  const ReceiptLineItem({
    required this.quantity,
    required this.productName,
    required this.unitPriceMinorUnits,
    required this.totalPriceMinorUnits,
    this.recipeSummary,
    this.selectionNotes = const [],
  });

  final int quantity;
  final String productName;
  final int unitPriceMinorUnits;
  final int totalPriceMinorUnits;
  final String? recipeSummary;
  final List<String> selectionNotes;
}

/// The full, structured content of one printed receipt — deliberately
/// separate from [ReceiptLineItem]'s ESC/POS byte encoding (see
/// `esc_pos_receipt_encoder.dart`) so the content can be unit-tested
/// without touching any byte-level formatting.
class ReceiptDocument {
  const ReceiptDocument({
    required this.restaurantName,
    required this.branchName,
    required this.tableName,
    required this.issuedAt,
    required this.receiptNumber,
    required this.lines,
    required this.subtotalMinorUnits,
    required this.discountMinorUnits,
    required this.totalMinorUnits,
    required this.currencyCode,
  });

  final String restaurantName;
  final String branchName;
  final String tableName;
  final DateTime issuedAt;
  final String receiptNumber;
  final List<ReceiptLineItem> lines;

  /// Sum of every line's [ReceiptLineItem.totalPriceMinorUnits] — before
  /// [discountMinorUnits].
  final int subtotalMinorUnits;

  /// `subtotalMinorUnits - totalMinorUnits`, never negative (clamped at 0 by
  /// the builder) — this check's own `computedTotalMinorUnits` is always
  /// authoritative, so a mismatch is treated as "no discount" rather than a
  /// negative one.
  final int discountMinorUnits;

  /// The check's real, authoritative `computedTotalMinorUnits` — never
  /// independently recomputed here.
  final int totalMinorUnits;

  final String currencyCode;
}
