import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../domain/models/branch_takeaway_settings.dart';

/// AP-6 Sprint 1 — the read side of `branchTakeawaySettings/{branchId}`
/// and the live "how many takeaway orders are currently deferred" count the
/// cashier/admin console badges need. Direct Firestore reads, mirroring
/// `FirestoreStockCountRepository`'s exact shape: `firestore.rules` allows
/// same-branch staff to read `branchTakeawaySettings` directly (unlike
/// `branchOperatingHours`, which has no client read at all), so no callable
/// round trip is needed for either query — only the WRITE side
/// (`updateTakeawayOperationStatus`) needs one, handled separately by
/// [TakeawayOperationsGateway].
abstract interface class TakeawayOperationsRepository {
  /// Live updates for one branch's current takeaway mode. `null` for a
  /// branch that has never had its mode touched — the caller renders this
  /// exactly like [TakeawayOperationStatus.active] (see
  /// `BranchTakeawaySettings`'s own "missing = active" convention, mirrored
  /// server-side in `functions/src/branchTakeawaySettings.ts`).
  Stream<BranchTakeawaySettings?> watchSettings(String branchId);

  /// The live count of this branch's currently-`scheduled` takeaway orders
  /// (deferred while the branch was `paused`, not yet promoted by
  /// `takeawayOperationsSweep.ts`) — the cashier console's pending-count
  /// badge. Deliberately a plain filtered-query listener (`docs.length`),
  /// not `AggregateQuery.count().snapshots()`: this codebase has no prior
  /// use of the real-time aggregate-count API, and a branch's own scheduled
  /// -order backlog is never large enough for the difference to matter.
  Stream<int> watchScheduledOrdersCount(String branchId);
}

class FirestoreTakeawayOperationsRepository
    implements TakeawayOperationsRepository {
  FirestoreTakeawayOperationsRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Stream<BranchTakeawaySettings?> watchSettings(String branchId) {
    return _firestore
        .collection('branchTakeawaySettings')
        .doc(branchId)
        .snapshots()
        .map((snap) => snap.exists ? _mapSettings(branchId, snap.data()!) : null);
  }

  @override
  Stream<int> watchScheduledOrdersCount(String branchId) {
    return _firestore
        .collection('orders')
        .where('branchId', isEqualTo: branchId)
        .where('status', isEqualTo: 'scheduled')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  BranchTakeawaySettings _mapSettings(String branchId, Map<String, dynamic> data) {
    return BranchTakeawaySettings(
      branchId: branchId,
      status: TakeawayOperationStatus.values.byName(data['status'] as String),
      busyDelayMinutes: (data['busyDelayMinutes'] as num?)?.toInt() ?? 0,
      pausedUntil: (data['pausedUntil'] as fs.Timestamp?)?.toDate(),
      updatedByStaffId: data['updatedByStaffId'] as String? ?? '',
      updatedAt: (data['updatedAt'] as fs.Timestamp?)?.toDate() ?? DateTime(0),
      revision: (data['revision'] as num?)?.toInt() ?? 1,
    );
  }
}
