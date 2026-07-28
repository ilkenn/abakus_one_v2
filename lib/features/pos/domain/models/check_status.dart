/// Lifecycle status of a [Check].
///
/// Deliberately only 3 values — a `Check`'s own status only tracks whether
/// it's still an editable pre-submission draft. Once `submitted`, whether
/// the check is actually *resolved* (paid and closed) is a question for
/// its `Order`'s own `OrderClosure` lifecycle (Phase 3 Sprint 3C), not
/// duplicated here — see `Check.isResolved`
/// (`docs/decisions.md` ADR-013).
enum CheckStatus { open, submitted, cancelled }

/// The check state machine: which [CheckStatus] transitions are valid.
abstract final class CheckStatusTransitions {
  CheckStatusTransitions._();

  static const Map<CheckStatus, Set<CheckStatus>> _allowed = {
    CheckStatus.open: {CheckStatus.submitted, CheckStatus.cancelled},
    CheckStatus.submitted: {},
    CheckStatus.cancelled: {},
  };

  static bool canTransition(CheckStatus from, CheckStatus to) {
    if (from == to) return false;
    return _allowed[from]?.contains(to) ?? false;
  }
}
