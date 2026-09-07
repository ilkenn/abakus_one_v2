/// Line-level kitchen-preparation lifecycle status for one
/// [KitchenWorkItem] — richer than [KitchenTicket]'s own binary
/// not-ready/ready `completedLineIds` tracking (Phase 3 Sprint 3D), which
/// stays untouched; this is an additional, coordinating layer on top of
/// it, not a replacement.
enum KitchenLineStatus {
  queued,
  acknowledged,
  preparing,
  ready,

  /// The line was cancelled before completion (e.g. the customer/order
  /// cancelled it) — terminal.
  cancelled,

  /// The kitchen cannot fulfill this line (e.g. out of stock) — terminal.
  /// Distinct from [cancelled]: an operational failure to fulfill, not a
  /// cancellation decision.
  unavailable,

  /// A previously [ready] line was explicitly recalled for correction —
  /// **never** a silent return to [preparing]; recall is its own,
  /// explicitly-audited state a line must pass through before resuming
  /// preparation (`ResumeRecalledKitchenWorkItem`).
  recalled,

  /// AP-5 Sprint 3 — the line was already [preparing] or [ready] (real
  /// food/packaging already consumed from stock) when its order/line was
  /// cancelled — terminal. Deliberately distinct from [cancelled] (which
  /// means nothing was ever consumed, so stock is reversible): [wasted]
  /// means the already-deducted stock stays deducted, recorded as real
  /// loss (`WasteRecord`), never returned to `branchStock`. Reachable
  /// from [preparing]/[ready] only — [queued]/[acknowledged] still
  /// terminate via the existing [cancelled], never [wasted], since
  /// nothing was consumed yet for them to waste.
  wasted,
}

/// The kitchen-line state machine: which [KitchenLineStatus] transitions
/// are valid. Mirrors `CashSessionStatusTransitions`/`OrderStatusTransitions`'s
/// single-source-of-truth shape.
///
/// **A completed ([ready]) line never silently returns to an earlier
/// state** — its only outgoing transition is to [recalled], an explicit,
/// distinct, always-audited correction state; [recalled] must then pass
/// back through [preparing] before it can reach [ready] again.
abstract final class KitchenLineStatusTransitions {
  KitchenLineStatusTransitions._();

  static const Map<KitchenLineStatus, Set<KitchenLineStatus>> _allowed = {
    KitchenLineStatus.queued: {
      KitchenLineStatus.acknowledged,
      KitchenLineStatus.cancelled,
      KitchenLineStatus.unavailable,
    },
    KitchenLineStatus.acknowledged: {
      KitchenLineStatus.preparing,
      KitchenLineStatus.cancelled,
      KitchenLineStatus.unavailable,
    },
    KitchenLineStatus.preparing: {
      KitchenLineStatus.ready,
      KitchenLineStatus.cancelled,
      KitchenLineStatus.unavailable,
      KitchenLineStatus.wasted,
    },
    KitchenLineStatus.ready: {
      KitchenLineStatus.recalled,
      KitchenLineStatus.wasted,
    },
    KitchenLineStatus.recalled: {
      KitchenLineStatus.preparing,
    },
    KitchenLineStatus.cancelled: {},
    KitchenLineStatus.unavailable: {},
    KitchenLineStatus.wasted: {},
  };

  static bool canTransition(KitchenLineStatus from, KitchenLineStatus to) {
    if (from == to) return false;
    return _allowed[from]?.contains(to) ?? false;
  }

  static bool isTerminal(KitchenLineStatus status) {
    return (_allowed[status] ?? const {}).isEmpty;
  }
}
