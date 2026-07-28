/// Generates a stable, session-local id for a new [PosOrderLineDraft].
///
/// **Deliberately separate from `OrderIdentityProvider`**
/// (`features/orders/domain/identity/order_identity.dart`) — that
/// abstraction is scoped to real business identities (`OrderId`/
/// `OrderNumber`) and is not extended for this. A draft-line id is
/// ephemeral, session-local correlation data, not a business identity; a
/// small, application-scope contract of its own is the right size for it
/// (`docs/decisions.md` ADR-012).
///
/// Application-layer, not domain: `AddProductToPosOrder` is the only
/// caller, and calls this itself — the UI never generates or even sees a
/// draft id, it only calls `notifier.addProduct(...)`.
abstract interface class PosOrderLineDraftIdGenerator {
  String nextDraftId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance (same honesty
/// scope as `InMemoryOrderIdentityProvider`, though this is not the same
/// contract).
class SequentialPosOrderLineDraftIdGenerator
    implements PosOrderLineDraftIdGenerator {
  SequentialPosOrderLineDraftIdGenerator({this.prefix = 'line'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextDraftId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
