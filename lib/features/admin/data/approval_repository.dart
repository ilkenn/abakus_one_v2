import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../domain/approval/approval_request.dart';

/// AP-2 final wiring — direct Firestore reads, now real
/// (`firestore.rules`'s `remoteApprovalRequests` rule: the requester
/// themselves, or a branch-scoped eligible responder). Two genuinely
/// different queries, each independently provable safe against the rule's
/// two disjoint branches (Firestore's rule engine proves a `list` query
/// safe per-branch via the query's own equality filters — a query mixing
/// both branches in one call could not be proven safe and would be denied
/// outright, so these stay two separate methods, never combined).
abstract interface class ApprovalRepository {
  /// Every request at this branch a manager/admin/tenantOwner is eligible
  /// to respond to (mirrors `RESPONSE_PERMISSION_BY_ACTION`'s real role
  /// set) — pending/escalated AND already-resolved, so the inbox can show
  /// a stale/expired/already-resolved state rather than the item simply
  /// vanishing once acted upon.
  Stream<List<ApprovalRequest>> watchEligibleApprovals({
    required String organizationId,
    required String branchId,
  });

  /// Every request this actor themselves created — their own status feed.
  Stream<List<ApprovalRequest>> watchMyRequests({required String actorUid});
}

class FirestoreApprovalRepository implements ApprovalRepository {
  FirestoreApprovalRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  // Lazily resolved — see `FirebasePlatformMemberRepository`'s identical
  // doc comment for why construction alone must never require a real
  // `Firebase.initializeApp()`.
  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Stream<List<ApprovalRequest>> watchEligibleApprovals({
    required String organizationId,
    required String branchId,
  }) {
    return _firestore
        .collection('remoteApprovalRequests')
        .where('organizationId', isEqualTo: organizationId)
        .where('branchId', isEqualTo: branchId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            [for (final doc in snapshot.docs) _mapRequest(doc.data())]);
  }

  @override
  Stream<List<ApprovalRequest>> watchMyRequests({required String actorUid}) {
    return _firestore
        .collection('remoteApprovalRequests')
        .where('requestedByActorUid', isEqualTo: actorUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            [for (final doc in snapshot.docs) _mapRequest(doc.data())]);
  }

  ApprovalRequest _mapRequest(Map<String, dynamic> data) {
    return ApprovalRequest(
      requestId: data['requestId'] as String,
      organizationId: data['organizationId'] as String,
      branchId: data['branchId'] as String,
      actionType: approvalActionTypeFromWire(data['actionType'] as String),
      requestedByActorUid: data['requestedByActorUid'] as String,
      targetAggregateRef: data['targetAggregateRef'] as String,
      status: approvalStatusFromWire(data['status'] as String),
      respondedByActorUid: data['respondedByActorUid'] as String?,
      respondedAt: (data['respondedAt'] as fs.Timestamp?)?.toDate(),
      escalatedTo: data['escalatedTo'] as String?,
      createdAt: (data['createdAt'] as fs.Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as fs.Timestamp).toDate(),
      version: data['version'] as int,
    );
  }
}

class UnavailableApprovalRepository implements ApprovalRepository {
  const UnavailableApprovalRepository();

  @override
  Stream<List<ApprovalRequest>> watchEligibleApprovals({
    required String organizationId,
    required String branchId,
  }) {
    return Stream.error(
        StateError('Approval backend is not available in this build.'));
  }

  @override
  Stream<List<ApprovalRequest>> watchMyRequests({required String actorUid}) {
    return Stream.error(
        StateError('Approval backend is not available in this build.'));
  }
}
