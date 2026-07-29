/// Lifecycle status of a [CourierShift] — a courier's financial-settlement
/// status (`CourierSettlementSessionStatus`, Sprint 3F) is deliberately a
/// separate concept; a shift ending never automatically closes a
/// settlement, and a settlement closing never implies a shift ended.
enum CourierShiftStatus {
  scheduled,
  awaitingManagerApproval,
  approved,
  active,
  ending,
  completed,
  rejected,
  cancelled,
  suspended,
}

/// The shift state machine — mirrors `CashSessionStatusTransitions`'s
/// single-source-of-truth shape.
abstract final class CourierShiftStatusTransitions {
  CourierShiftStatusTransitions._();

  static const Map<CourierShiftStatus, Set<CourierShiftStatus>> _allowed = {
    CourierShiftStatus.scheduled: {
      CourierShiftStatus.awaitingManagerApproval,
      CourierShiftStatus.cancelled,
    },
    CourierShiftStatus.awaitingManagerApproval: {
      CourierShiftStatus.approved,
      CourierShiftStatus.rejected,
    },
    CourierShiftStatus.approved: {
      CourierShiftStatus.active,
      CourierShiftStatus.cancelled,
    },
    CourierShiftStatus.active: {
      CourierShiftStatus.ending,
      CourierShiftStatus.suspended,
    },
    CourierShiftStatus.ending: {
      CourierShiftStatus.completed,
      CourierShiftStatus.active, // an ending request may be withdrawn
    },
    CourierShiftStatus.suspended: {
      CourierShiftStatus.active,
      CourierShiftStatus.completed,
    },
    CourierShiftStatus.completed: {},
    CourierShiftStatus.rejected: {},
    CourierShiftStatus.cancelled: {},
  };

  static bool canTransition(CourierShiftStatus from, CourierShiftStatus to) {
    if (from == to) return false;
    return _allowed[from]?.contains(to) ?? false;
  }

  static bool isTerminal(CourierShiftStatus status) {
    return (_allowed[status] ?? const {}).isEmpty;
  }
}
