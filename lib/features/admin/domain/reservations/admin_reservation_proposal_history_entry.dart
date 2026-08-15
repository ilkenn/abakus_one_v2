/// Mirrors the backend's canonical `reservationChangeProposals.status`
/// enum (`respondToReservation.ts`/`respondToProposedChange.ts`/
/// `reservationSweep.ts`) — never shown to staff as a raw string.
enum AdminProposalStatus {
  pendingCustomerResponse,
  accepted,
  rejected,
  expired;

  static AdminProposalStatus fromName(String name) =>
      AdminProposalStatus.values.byName(name);
}

/// One entry in a reservation's full change-proposal history —
/// `reservationChangeProposals` documents for one `reservationId`,
/// ordered newest-first. Unlike the customer-facing flow (which only ever
/// sees the *current* proposal, denormalized onto the Reservation
/// document itself — `reservationChangeProposals` stays org-staff-read-
/// only, Faz R.1B's own scope decision), staff can read this collection
/// directly: `firestore.rules` already grants `allow read` to an org
/// member for their own tenant's proposals, so this is a direct Firestore
/// stream, not a new callable.
class AdminReservationProposalHistoryEntry {
  const AdminReservationProposalHistoryEntry({
    required this.proposalId,
    required this.status,
    required this.fromTime,
    required this.fromAreaId,
    required this.proposedTime,
    required this.proposedAreaId,
    required this.createdByStaffId,
    required this.createdAt,
    required this.customerResponseDeadlineAt,
    this.respondedAt,
  });

  final String proposalId;
  final AdminProposalStatus status;
  final DateTime fromTime;
  final String fromAreaId;
  final DateTime proposedTime;
  final String proposedAreaId;
  final String createdByStaffId;
  final DateTime createdAt;
  final DateTime customerResponseDeadlineAt;
  final DateTime? respondedAt;
}
