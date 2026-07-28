import '../../../cart/domain/models/cart_item.dart';

/// One line in an in-progress [PosOrderSession] — a stable, session-local
/// identity ([id]) wrapped around a [CartItem].
///
/// **Why this wrapper exists**: `PosOrderSession.lines` used to be a raw
/// `List<CartItem>`, and every mutation (`UpdatePosOrderLine`,
/// `RemovePosOrderLine`, a line discount's `targetOrderLineId`) had to
/// address a line by its array index — fragile the moment a line above it
/// is removed. [id] is generated once, by
/// `PosOrderLineDraftIdGenerator`, when a line is first added
/// (`AddProductToPosOrder`), and never changes for that line's lifetime in
/// the session.
///
/// [CartItem] itself is deliberately left untouched (see
/// `docs/decisions.md` ADR-012) — it is the customer app's own cart line
/// model too; adding session-only identity to it would leak a POS concern
/// into a shared type. Wrapping it here keeps the POS-only concept POS-
/// only.
class PosOrderLineDraft {
  const PosOrderLineDraft({required this.id, required this.item});

  /// Session-local identity — never a business identity, never generated
  /// by domain code (see `PosOrderLineDraftIdGenerator`'s own doc
  /// comment).
  final String id;

  final CartItem item;

  PosOrderLineDraft copyWith({String? id, CartItem? item}) {
    return PosOrderLineDraft(id: id ?? this.id, item: item ?? this.item);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PosOrderLineDraft && other.id == id && other.item == item);
  }

  @override
  int get hashCode => Object.hash(id, item);
}
