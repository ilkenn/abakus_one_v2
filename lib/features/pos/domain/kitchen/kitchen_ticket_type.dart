/// What a [KitchenTicket] documents — distinct from whether this
/// particular print is a copy (see [KitchenTicket.isCopy]): a ticket's
/// [type] and its copy-ness are independent dimensions (a delta ticket can
/// itself be reprinted as a copy).
enum KitchenTicketType {
  /// The first ticket fired for an order.
  initial,

  /// An order-line addition/change fired after the initial ticket (the
  /// kitchen must never re-cook the whole order for one added item).
  delta,

  /// An order or line cancellation, fired so the kitchen stops/discards
  /// work already in progress.
  cancellation,
}
