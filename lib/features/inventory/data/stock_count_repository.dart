import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../domain/stock_count.dart';

abstract interface class StockCountRepository {
  Future<void> save(StockCount count);
  Future<StockCount?> findById(String id);
  Future<List<StockCount>> findByBranchId(String branchId);
}

class InMemoryStockCountRepository implements StockCountRepository {
  final Map<String, StockCount> _byId = {};

  @override
  Future<void> save(StockCount count) async => _byId[count.id] = count;

  @override
  Future<StockCount?> findById(String id) async => _byId[id];

  @override
  Future<List<StockCount>> findByBranchId(String branchId) async {
    return List.unmodifiable(_byId.values.where((c) => c.branchId == branchId));
  }
}

/// AP-5 Sprint 6 — direct Firestore reads of the real `stockCounts`
/// collection `submitStockCount.ts` (Sprint 3) writes, mirroring
/// `FirestoreApprovalRepository`'s exact shape. `save` is a deliberate
/// no-op: `firestore.rules` denies every client write on this collection
/// (`allow write: if false` — Cloud Function only), matching
/// `FirestoreKitchenWorkItemRepository`'s own identical precedent.
class FirestoreStockCountRepository implements StockCountRepository {
  FirestoreStockCountRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Future<void> save(StockCount count) async {}

  @override
  Future<StockCount?> findById(String id) async {
    final snap = await _firestore.collection('stockCounts').doc(id).get();
    if (!snap.exists) return null;
    return _mapCount(id, snap.data()!);
  }

  @override
  Future<List<StockCount>> findByBranchId(String branchId) async {
    final snap = await _firestore
        .collection('stockCounts')
        .where('branchId', isEqualTo: branchId)
        .get();
    return List.unmodifiable(
        [for (final doc in snap.docs) _mapCount(doc.id, doc.data())]);
  }

  StockCount _mapCount(String id, Map<String, dynamic> data) {
    return StockCount(
      id: id,
      branchId: data['branchId'] as String,
      locationId: data['locationId'] as String,
      status: StockCountStatus.values.byName(data['status'] as String),
      startedByStaffId: data['startedByStaffId'] as String,
      startedAt: (data['startedAt'] as fs.Timestamp).toDate(),
      submittedAt: (data['submittedAt'] as fs.Timestamp?)?.toDate(),
      approvedByStaffId: data['approvedByStaffId'] as String?,
      approvedAt: (data['approvedAt'] as fs.Timestamp?)?.toDate(),
      rejectionReason: data['rejectionReason'] as String?,
    );
  }
}
