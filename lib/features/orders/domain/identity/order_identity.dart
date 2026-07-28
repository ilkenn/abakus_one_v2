import '../models/order_id.dart';
import '../models/order_number.dart';

/// Source of a new [OrderId]/[OrderNumber] pair — the one seam that's
/// allowed to produce these values. Nothing else in this codebase
/// generates an order identity (see `OrderId`/`OrderNumber`'s own doc
/// comments): not a UI widget, not an application use case, not a domain
/// model, and never via a timestamp/random value/UUID package inlined at
/// the call site.
abstract interface class OrderIdentityProvider {
  Future<OrderId> nextOrderId();
  Future<OrderNumber> nextOrderNumber();
}

/// Deterministic, collision-safe **within one runtime** implementation —
/// intended only for tests and local development, explicitly not a
/// production identity scheme (that needs server-side coordination so
/// concurrent devices never collide — see `docs/business_rules.md`
/// BR-ORDER-005). A future backend-backed implementation replaces this
/// one behind the same [OrderIdentityProvider] interface; nothing that
/// depends on the interface needs to change when that happens.
///
/// [nextOrderId]/[nextOrderNumber] share one monotonically increasing
/// counter per instance — two calls from the same instance can never
/// produce the same value, but two separate instances (e.g. two isolates,
/// or the app restarting) each start back at 1. That's the "within one
/// runtime" guarantee, not a stronger one.
class InMemoryOrderIdentityProvider implements OrderIdentityProvider {
  InMemoryOrderIdentityProvider({this.prefix = 'local'});

  /// Distinguishes one instance's sequence from another's in tests that
  /// run multiple providers side by side (e.g. asserting they never
  /// collide) — not a production namespacing scheme.
  final String prefix;

  int _sequence = 0;

  @override
  Future<OrderId> nextOrderId() async {
    _sequence += 1;
    return OrderId('$prefix-order-$_sequence');
  }

  @override
  Future<OrderNumber> nextOrderNumber() async {
    // A distinct counter from nextOrderId's, so calling one does not
    // consume the other's sequence — OrderId and OrderNumber are
    // independent identities (see their own doc comments).
    _numberSequence += 1;
    return OrderNumber('$prefix-${_numberSequence.toString().padLeft(4, '0')}');
  }

  int _numberSequence = 0;
}
