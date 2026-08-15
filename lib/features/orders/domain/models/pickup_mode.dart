/// How a takeaway (`OrderChannel.takeaway`) order's pickup time was chosen.
///
/// [asap] — the customer is already physically present (Gel Al kiosk QR,
/// Scenario 1) or asked for the earliest possible pickup; `Order.pickupTime`
/// may be `null`. [scheduled] — a specific pickup time was chosen (in-app
/// Takeaway, Scenario 2); `Order.pickupTime` must be non-null (enforced by
/// `Order`'s own constructor assertion).
///
/// `null` for every non-takeaway `Order` — this field has no meaning outside
/// the takeaway flow, mirroring how `Order.tableId`/`tableSessionId` are
/// `null` outside the dine-in-QR flow.
enum PickupMode { asap, scheduled }
