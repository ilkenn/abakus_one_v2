/// Whether a [ChannelOperationPolicy]'s channel is currently taking new
/// orders.
///
/// `emergencyClosed` is deliberately distinct from `closed`: an ordinary
/// `closed` is a normal, staff-reversible pause; `emergencyClosed` is only
/// reachable via `EmergencyCloseDeliveryChannels` and only leaves that state
/// via an explicit, authorized staff action — never automatically, and
/// never merely by the branch's regular open/close routine (see
/// `docs/business_rules.md` — platforms are meant to stay open without
/// staff reopening them every morning; an emergency stop must not be
/// silently undone by that same routine).
enum ChannelOperationalState { open, busy, closed, emergencyClosed }

/// The channel operational-state machine: which [ChannelOperationalState]
/// transitions are valid.
///
/// Mirrors `OrderStatusTransitions`'s single-source-of-truth shape.
abstract final class ChannelOperationalStateTransitions {
  ChannelOperationalStateTransitions._();

  static const Map<ChannelOperationalState, Set<ChannelOperationalState>>
      _allowed = {
    ChannelOperationalState.open: {
      ChannelOperationalState.busy,
      ChannelOperationalState.closed,
      ChannelOperationalState.emergencyClosed,
    },
    ChannelOperationalState.busy: {
      ChannelOperationalState.open,
      ChannelOperationalState.closed,
      ChannelOperationalState.emergencyClosed,
    },
    ChannelOperationalState.closed: {
      ChannelOperationalState.open,
      ChannelOperationalState.busy,
      ChannelOperationalState.emergencyClosed,
    },
    ChannelOperationalState.emergencyClosed: {
      ChannelOperationalState.open,
    },
  };

  static bool canTransition(
    ChannelOperationalState from,
    ChannelOperationalState to,
  ) {
    if (from == to) return false;
    return _allowed[from]?.contains(to) ?? false;
  }
}
