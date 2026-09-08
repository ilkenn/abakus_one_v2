/// AP-2 final wiring — mirrors `functions/src/remoteApproval.ts`'s
/// `ApprovalRequestRecord` field-for-field. `payloadHash` is deliberately
/// never carried into this client model — it has no legitimate UI use and
/// this is the structural way "no sensitive payload in the UI" is kept
/// true even as this domain evolves.
library;

enum ApprovalActionType {
  deviceActivation,
  checkFinancialAdjustment,
  acceptedLineCancellation,
  boncukBalanceCorrection,
  // AP-4 Wave A (ADR-033/044) — a staff-requested refund requiring manager
  // approval before any money moves.
  paymentRefund,
  // AP-4 Wave B (ADR-045) — cash register lifecycle actions. Unlike every
  // action above, these four also have a real REJECTION effect server-side
  // (`remoteApproval.ts`'s `REJECTION_HANDLERS`) — a rejected request is
  // never a client-side no-op for these.
  cashSessionOpen,
  cashMovement,
  cashAdjustment,
  cashReconciliation,
  // AP-5 Sprint 6 — mirrors the server-side `ApprovalActionType` union
  // (`functions/src/remoteApproval.ts`) added in Sprint 3 alongside
  // `submitStockCount`. Never wired into this Dart enum until now — the
  // Approval Inbox would have thrown `ArgumentError` on any real stock
  // -count approval request before this addition.
  stockCountAdjustment,
}

enum ApprovalStatus {
  pending,
  approved,
  rejected,
  expired,
  escalated,
  cancelled
}

ApprovalActionType approvalActionTypeFromWire(String value) {
  switch (value) {
    case 'deviceActivation':
      return ApprovalActionType.deviceActivation;
    case 'checkFinancialAdjustment':
      return ApprovalActionType.checkFinancialAdjustment;
    case 'acceptedLineCancellation':
      return ApprovalActionType.acceptedLineCancellation;
    case 'boncukBalanceCorrection':
      return ApprovalActionType.boncukBalanceCorrection;
    case 'paymentRefund':
      return ApprovalActionType.paymentRefund;
    case 'cashSessionOpen':
      return ApprovalActionType.cashSessionOpen;
    case 'cashMovement':
      return ApprovalActionType.cashMovement;
    case 'cashAdjustment':
      return ApprovalActionType.cashAdjustment;
    case 'cashReconciliation':
      return ApprovalActionType.cashReconciliation;
    case 'stockCountAdjustment':
      return ApprovalActionType.stockCountAdjustment;
    default:
      throw ArgumentError('Unknown approval action type: $value');
  }
}

ApprovalStatus approvalStatusFromWire(String value) {
  switch (value) {
    case 'pending':
      return ApprovalStatus.pending;
    case 'approved':
      return ApprovalStatus.approved;
    case 'rejected':
      return ApprovalStatus.rejected;
    case 'expired':
      return ApprovalStatus.expired;
    case 'escalated':
      return ApprovalStatus.escalated;
    case 'cancelled':
      return ApprovalStatus.cancelled;
    default:
      throw ArgumentError('Unknown approval status: $value');
  }
}

class ApprovalRequest {
  const ApprovalRequest({
    required this.requestId,
    required this.organizationId,
    required this.branchId,
    required this.actionType,
    required this.requestedByActorUid,
    required this.targetAggregateRef,
    required this.status,
    this.respondedByActorUid,
    this.respondedAt,
    this.escalatedTo,
    required this.createdAt,
    required this.expiresAt,
    required this.version,
  });

  final String requestId;
  final String organizationId;
  final String branchId;
  final ApprovalActionType actionType;
  final String requestedByActorUid;
  final String targetAggregateRef;
  final ApprovalStatus status;
  final String? respondedByActorUid;
  final DateTime? respondedAt;
  final String? escalatedTo;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int version;

  bool get isRespondable => status == ApprovalStatus.pending;

  /// A safe, non-sensitive summary derived purely from the target's own
  /// Firestore path — no need to fetch the target document just to show
  /// which device this request concerns. Falls back to the raw ref if the
  /// path doesn't match the expected `trustedDeviceRegistrations/{docId}`
  /// shape (forward-compatible with a future action type).
  String get targetDeviceId {
    final parts = targetAggregateRef.split('/');
    if (parts.length == 2 && parts[0] == 'trustedDeviceRegistrations') {
      final docIdParts = parts[1].split('_');
      if (docIdParts.length >= 3) return docIdParts.last;
    }
    return targetAggregateRef;
  }

  /// AP-5 Sprint 6 — same "safe summary from the ref's own path" shape as
  /// [targetDeviceId], for a [ApprovalActionType.stockCountAdjustment]
  /// request's `targetAggregateRef` (`stockCounts/{countId}`, set by
  /// `submitStockCount.ts`'s own `createApprovalRequest` call). `null`
  /// when the ref doesn't match that shape (any other action type).
  String? get stockCountId {
    final parts = targetAggregateRef.split('/');
    if (parts.length == 2 && parts[0] == 'stockCounts') {
      return parts[1];
    }
    return null;
  }
}
