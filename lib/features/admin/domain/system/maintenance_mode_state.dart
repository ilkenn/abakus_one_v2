/// A single, system-wide maintenance-mode flag — Phase 6O
/// (`docs/decisions.md` ADR-023). "Maintenance mode foundation" — a
/// real, admin-toggleable, audited state, but **nothing reads it**: no
/// customer-facing screen, order flow, or POS action checks
/// `isActive` today. Distinct from `Branch.emergencyStopped` (Phase 6D
/// — one specific branch, "the whole branch, admin-only") — this is a
/// single global flag, not per-branch.
class MaintenanceModeState {
  const MaintenanceModeState({
    this.isActive = false,
    this.reason,
    this.changedByStaffId,
    this.changedAt,
    required this.revision,
  });

  final bool isActive;
  final String? reason;
  final String? changedByStaffId;
  final DateTime? changedAt;
  final int revision;

  MaintenanceModeState copyWith({
    required bool isActive,
    String? reason,
    bool clearReason = false,
    required String changedByStaffId,
    required DateTime changedAt,
    required int revision,
  }) {
    return MaintenanceModeState(
      isActive: isActive,
      reason: clearReason ? null : (reason ?? this.reason),
      changedByStaffId: changedByStaffId,
      changedAt: changedAt,
      revision: revision,
    );
  }
}
