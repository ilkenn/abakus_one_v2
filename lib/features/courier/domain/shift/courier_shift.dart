import 'courier_shift_status.dart';

/// One courier's work shift — append-only via [revision], mirrors
/// `CashSession`/`CourierSettlementSession`'s shape exactly. Deliberately
/// carries no financial data at all: settlement remains entirely
/// Sprint 3F's `CourierSettlementSession`'s responsibility, referenced
/// only loosely (by courier + time window), never duplicated here.
class CourierShift {
  const CourierShift({
    required this.id,
    required this.courierId,
    required this.branchId,
    required this.status,
    required this.requestedAt,
    this.approvedByStaffId,
    this.approvedAt,
    this.startedAt,
    this.endedAt,
    this.rejectionReason,
    this.cancellationReason,
    required this.revision,
  });

  final String id;
  final String courierId;
  final String branchId;
  final CourierShiftStatus status;
  final DateTime requestedAt;

  /// Never equal to [courierId] — enforced by `ReviewCourierShift`
  /// (self-approval is structurally blocked, mirrors
  /// `ApproveCourierSettlement`'s reused `SelfApprovalNotAllowedViolation`).
  final String? approvedByStaffId;

  final DateTime? approvedAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? rejectionReason;
  final String? cancellationReason;

  /// Optimistic-concurrency counter — starts at 1.
  final int revision;

  bool get isActive =>
      status == CourierShiftStatus.active ||
      status == CourierShiftStatus.ending;

  CourierShift copyWith({
    CourierShiftStatus? status,
    String? approvedByStaffId,
    DateTime? approvedAt,
    DateTime? startedAt,
    DateTime? endedAt,
    String? rejectionReason,
    String? cancellationReason,
    int? revision,
  }) {
    return CourierShift(
      id: id,
      courierId: courierId,
      branchId: branchId,
      status: status ?? this.status,
      requestedAt: requestedAt,
      approvedByStaffId: approvedByStaffId ?? this.approvedByStaffId,
      approvedAt: approvedAt ?? this.approvedAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      revision: revision ?? this.revision,
    );
  }
}
