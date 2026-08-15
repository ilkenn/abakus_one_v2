import '../../../reservation/domain/models/reservation_status.dart';

/// The admin-facing read model for one reservation — what
/// `listReservationsForBranch` returns per item, and what the detail
/// panel renders directly (no separate "detail" shape: the list endpoint
/// already returns everything staff need; the detail panel is the same
/// data, just laid out differently). Deliberately distinct from the
/// customer-facing `ReservationSummary` (`features/reservation/domain/
/// models/reservation_summary.dart`) — that model excludes staff-only
/// fields (contact name, assigned table) the customer's own detail screen
/// has no reason to show; this one excludes nothing a staff member is
/// authorized to see. Internal hold/bucket ids are never included in
/// either — this callable's own response shape structurally can't leak
/// them.
class AdminReservationSummary {
  const AdminReservationSummary({
    required this.id,
    required this.status,
    required this.partySize,
    required this.requestedTime,
    required this.requestedAreaId,
    required this.contactFirstName,
    required this.contactLastName,
    this.confirmedTime,
    this.confirmedAreaId,
    this.assignedTableId,
    this.preorderOrderId,
    this.activeProposalCustomerResponseDeadlineAt,
  });

  final String id;
  final ReservationStatus status;
  final int partySize;
  final DateTime requestedTime;
  final String requestedAreaId;
  final String contactFirstName;
  final String contactLastName;
  final DateTime? confirmedTime;
  final String? confirmedAreaId;
  final String? assignedTableId;
  final String? preorderOrderId;

  /// Non-null only while [status] is [ReservationStatus.changeProposed] —
  /// the response-urgency deadline the list/calendar surfaces so staff can
  /// prioritize an expiring proposal.
  final DateTime? activeProposalCustomerResponseDeadlineAt;

  String get contactFullName => '$contactFirstName $contactLastName'.trim();

  /// The area a reservation is actually operating under right now —
  /// [confirmedAreaId] once confirmed, [requestedAreaId] before that.
  String get effectiveAreaId => confirmedAreaId ?? requestedAreaId;

  /// The time a reservation is actually operating under right now —
  /// [confirmedTime] once confirmed, [requestedTime] before that.
  DateTime get effectiveTime => confirmedTime ?? requestedTime;

  bool get hasPreorder => preorderOrderId != null;
  bool get hasAssignedTable => assignedTableId != null;
}
