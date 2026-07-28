import '../../../../shared/models/money.dart';

/// The immutable record of opening a [CashDrawer] into a new
/// [CashSession] — a value object embedded in [CashSession], not a
/// separate top-level append-only aggregate: it never changes once the
/// session exists, and it has no lifecycle of its own beyond "this
/// session was opened with these facts."
class CashOpening {
  const CashOpening({
    required this.openedByStaffId,
    required this.openedAt,
    required this.openingFloatAmount,
  });

  final String openedByStaffId;
  final DateTime openedAt;

  /// The starting cash placed in the drawer — always non-negative. This
  /// amount is also recorded as the session's first `CashMovement`
  /// (`CashMovementType.openingFloat`), so `CashCount`'s expected-amount
  /// computation (a straight sum of every movement) does not need to
  /// special-case the opening float separately.
  final Money openingFloatAmount;
}
