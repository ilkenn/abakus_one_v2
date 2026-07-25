/// Canonical origin of an [OrderModel], independent of how the order was
/// prepared or fulfilled.
///
/// `dineInQr` is the channel a table-QR order (see
/// `docs/table_qr_architecture.md`) will use once ordering submission is
/// implemented; this enum only establishes the vocabulary in this phase.
enum OrderChannel {
  dineInQr,
  dineInStaff,
  takeaway,
  delivery,
  reservationPreorder,
}
