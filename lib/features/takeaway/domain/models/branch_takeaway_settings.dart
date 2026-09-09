/// AP-6 Sprint 1 — a branch's live, staff-controlled takeaway operational
/// mode. **Independent from `branchOperatingHours`/`ChannelOperationPolicy`**
/// (see `functions/src/branchOperatingHours.ts`'s own doc comment for that
/// existing separation-of-concerns precedent, which this mirrors): those
/// answer "is the branch open at all"; this answers "how should a takeaway
/// order submitted right now be timed/accepted."
enum TakeawayOperationStatus {
  /// Normal operation — takeaway orders are accepted and confirmed exactly
  /// as before this sprint.
  active,

  /// The branch is accepting orders but running behind — a new order's
  /// [busyDelayMinutes] is added on top of the standard prep/delivery
  /// estimate. Never rejects an order; only shifts its estimate.
  busy,

  /// The branch is not currently working new takeaway orders at all, but
  /// still accepts them — each is held as `OrderStatus.scheduled` until
  /// [pausedUntil], then promoted automatically by
  /// `takeawayOperationsSweep.ts`. Never a hard "closed, come back later"
  /// rejection.
  paused,
}

/// The fixed set of extra-delay values `updateTakeawayOperationStatus`
/// accepts for [BranchTakeawaySettings.busyDelayMinutes] — validated at the
/// callable boundary, not narrowed into its own enum (mirrors how
/// `Quantity`/`Money` keep a numeric type and validate at the boundary
/// rather than force an enum for what is really a bounded integer).
const List<int> kTakeawayBusyDelayMinuteOptions = [0, 15, 30, 45, 60];

/// A branch's current takeaway operational mode — `branchTakeawaySettings/
/// {branchId}` (Cloud Function–only write, via `updateTakeawayOperationStatus`;
/// see `firestore.rules`). One document per branch, mirroring
/// `branchOperatingHours`'s 1:1-branch-keyed shape.
class BranchTakeawaySettings {
  const BranchTakeawaySettings({
    required this.branchId,
    required this.status,
    this.busyDelayMinutes = 0,
    this.pausedUntil,
    required this.updatedByStaffId,
    required this.updatedAt,
    this.revision = 1,
  }) : assert(
          status != TakeawayOperationStatus.paused || pausedUntil != null,
          'status == TakeawayOperationStatus.paused requires a non-null pausedUntil',
        );

  final String branchId;
  final TakeawayOperationStatus status;

  /// Meaningful only when [status] is [TakeawayOperationStatus.busy] — one
  /// of [kTakeawayBusyDelayMinuteOptions]. `0` for every other status.
  final int busyDelayMinutes;

  /// The absolute time this pause ends — required when [status] is
  /// [TakeawayOperationStatus.paused], `null` otherwise. Always a fully-
  /// resolved timestamp: the four fixed presets (30 min / 1 hour / 2 hours /
  /// end-of-day) and the custom-date option are all resolved to an absolute
  /// instant client-side before `updateTakeawayOperationStatus` is called —
  /// this field never stores a raw duration.
  final DateTime? pausedUntil;

  final String updatedByStaffId;
  final DateTime updatedAt;

  /// Optimistic-concurrency counter, incremented on every mode change —
  /// same convention as `Order.version`.
  final int revision;

  /// Whether a takeaway order submitted right now should be deferred to
  /// [OrderStatus.scheduled] rather than accepted immediately — true only
  /// while actually [TakeawayOperationStatus.paused] (a [pausedUntil] that
  /// has already passed is stale data the sweep just hasn't reverted yet;
  /// [now] lets a caller treat it as already-active without waiting on
  /// that sweep).
  bool isPausedAt(DateTime now) =>
      status == TakeawayOperationStatus.paused &&
      (pausedUntil == null || now.isBefore(pausedUntil!));

  BranchTakeawaySettings copyWith({
    String? branchId,
    TakeawayOperationStatus? status,
    int? busyDelayMinutes,
    DateTime? pausedUntil,
    String? updatedByStaffId,
    DateTime? updatedAt,
    int? revision,
  }) {
    return BranchTakeawaySettings(
      branchId: branchId ?? this.branchId,
      status: status ?? this.status,
      busyDelayMinutes: busyDelayMinutes ?? this.busyDelayMinutes,
      pausedUntil: pausedUntil ?? this.pausedUntil,
      updatedByStaffId: updatedByStaffId ?? this.updatedByStaffId,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
    );
  }
}
