/// Mirrors the backend's canonical `Reservation.status` enum
/// (`functions/src/submitReservation.ts` et al.) — never shown to the
/// customer as a raw string (`ReservationStatusCopy` in the presentation
/// layer maps each value to approved Turkish copy).
///
/// Faz R.3B added [completed]/[noShow] — the two remaining terminal
/// operational outcomes, alongside the pre-existing [rejected]/[cancelled].
/// Every terminal status ([rejected], [cancelled], [completed], [noShow])
/// is final: a Reservation never re-enters active lifecycle from any of
/// them (`docs/business_rules.md` BR-RESERVATION-039).
enum ReservationStatus {
  pendingRestaurantApproval,
  changeProposed,
  confirmed,
  rejected,
  cancelled,
  completed,
  noShow;

  static ReservationStatus fromName(String name) =>
      ReservationStatus.values.byName(name);

  /// Whether this status is a final, terminal outcome — never re-enters
  /// active lifecycle. Faz R.3B §1's own canonical terminal set.
  bool get isTerminal =>
      this == ReservationStatus.rejected ||
      this == ReservationStatus.cancelled ||
      this == ReservationStatus.completed ||
      this == ReservationStatus.noShow;
}
