/// A kitchen preparation station a [KitchenWorkItem] may be routed to.
///
/// The default Abaküs configuration routes every line to [shared] — the
/// same single-queue behavior `KitchenDisplayScreen` already has (Phase 3
/// Sprint 3D, station filter chips present but disabled). Additive-only
/// extension point: adding a new station is a closed-enum edit (the same
/// kind of change `CashMovementType`/`PosAuthorizedAction` already went
/// through across sprints), never an aggregate rewrite — no other Phase 4
/// type encodes station-specific behavior beyond routing/filtering by
/// this value.
enum KitchenStation {
  shared,
  hot,
  cold,
  beverage,
  dessert,
  packing,
}
