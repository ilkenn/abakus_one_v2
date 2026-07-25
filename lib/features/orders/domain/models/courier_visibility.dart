/// Whether a courier's live delivery status/location may be shown to the
/// customer for a specific [OrderModel].
///
/// **Business rule (mandatory):** a courier who is out delivering a
/// *different* order must never be shown to this customer, even once this
/// order's [OrderStatus.outForDelivery] stage has technically been reached
/// (a courier can be assigned/dispatched before actually starting this
/// customer's leg of their route). Visibility is therefore modeled as its
/// own explicit field, independent of [OrderStatus] — reaching
/// `outForDelivery` alone must never imply [visibleToCustomer]. Only an
/// explicit action recorded against *this* order (a courier actually
/// departing for *this* customer) may set it.
///
/// There is no real GPS/live-map integration behind this — see
/// `ActiveOrderScreen`'s delivery placeholder panel, which renders an
/// honest, explicitly-labeled placeholder in both states rather than a fake
/// live map.
enum CourierVisibility {
  /// Default for every order. No courier location/live status is shown —
  /// either no courier has been dispatched yet, or one has been dispatched
  /// but is still completing another delivery first.
  hidden,

  /// A courier has started this customer's leg specifically. Only valid
  /// while [OrderModel.lifecycleStatus] is [OrderStatus.outForDelivery] —
  /// see `OrdersNotifier.setCourierVisibleToCustomer`.
  visibleToCustomer,
}
