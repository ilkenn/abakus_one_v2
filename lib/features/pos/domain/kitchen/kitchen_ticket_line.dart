/// One product block on a [KitchenTicket] — a full, frozen snapshot, never
/// a live product reference (mirrors `OrderLine`/
/// `OrderLineModifierSelection`'s own "snapshot, don't reference"
/// principle).
///
/// [id] is generated fresh when the ticket is fired (`FireKitchenTicket`)
/// — deliberately **not** the same id as the `OrderLine` it was built
/// from (`OrderLine` has no stable id at all — see `docs/decisions.md`
/// ADR-013's note on why post-submission item-level correction is
/// deferred). Giving `KitchenTicketLine` its own id sidesteps that gap
/// entirely for this sprint's actual need (per-line ready/complete
/// tracking on the ticket, not on the order).
class KitchenTicketLine {
  const KitchenTicketLine({
    required this.id,
    required this.productName,
    required this.quantity,

    /// Full ingredient/modifier snapshot as flat display text (e.g.
    /// "Ekstra Peynir x1", "Acı Sos") — a ready-made product still prints
    /// its complete ingredient snapshot here, per the explicit
    /// requirement; it is never omitted just because the product wasn't
    /// built to order.
    this.ingredientSummary = const [],
    this.note = '',

    /// Allergen or critical preparation warnings. Always empty this
    /// sprint — no allergen data source exists anywhere in the current
    /// menu model (`MenuProduct` has no allergen field). Kept as a list
    /// of free-text warnings, not fabricated, so the ticket layout is
    /// ready the moment that data source exists.
    this.warnings = const [],
  });

  final String id;
  final String productName;
  final int quantity;
  final List<String> ingredientSummary;
  final String note;
  final List<String> warnings;
}
