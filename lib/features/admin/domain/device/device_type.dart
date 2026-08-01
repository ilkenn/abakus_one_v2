/// The kind of physical/virtual device the Admin Platform's device
/// registry can represent — Phase 6L (`docs/decisions.md` ADR-023).
///
/// [kitchenDisplay] and [courierDevice] are backed by real, existing
/// domain aggregates (`KitchenDisplayDevice`, `CourierDevice`) owned by
/// their own bounded contexts — the registry only *projects* them,
/// never owns or mutates their full record. [posTerminal], [printer],
/// and [paymentTerminal] have **no backing domain aggregate anywhere in
/// this codebase** — for those, `AdminDeviceRegistration` is the only
/// record that exists at all, a deliberately minimal foundation per the
/// brief's own "do not fabricate complete management capability."
enum DeviceType {
  kitchenDisplay,
  courierDevice,
  posTerminal,
  printer,
  paymentTerminal,
}
