/// A customer-selectable reservation area (e.g. "Bahçe"/"İç Mekân") — the
/// server-authoritative, UI-shaped subset `getReservationBranchInfo`
/// returns. Never a physical table — the customer never selects one
/// (`docs/decisions.md` ADR-027's own product invariant, unchanged by this
/// phase). Branch-configurable: no area name is ever hardcoded in the UI.
class ReservationArea {
  const ReservationArea({required this.id, required this.displayName});

  final String id;
  final String displayName;
}
