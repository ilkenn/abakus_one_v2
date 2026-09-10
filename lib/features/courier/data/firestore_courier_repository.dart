import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../../shared/models/courier_type.dart';
import '../domain/identity/courier.dart';
import '../domain/identity/courier_registry_status.dart';
import '../domain/identity/courier_status.dart';
import '../domain/identity/courier_vehicle_type.dart';
import 'courier_repository.dart';

/// AP-6 Sprint 2 — direct Firestore reads/writes of the real `couriers`
/// collection `setCourier.ts`/`assignCourierToOrder.ts`/
/// `markCourierReturned.ts` write, mirroring `FirestoreStockCountRepository`'s
/// exact shape: implements the SAME [CourierRepository] interface the
/// 220-file in-memory courier domain already uses (reused, not duplicated),
/// wired via its own, separate provider (`courier_dispatch_dependencies_
/// provider.dart` — never the courier module's own `courierRepositoryProvider`,
/// per that file's own "courier and KDS/POS dependency graphs stay parallel"
/// rule).
///
/// [save] is a deliberate no-op: `firestore.rules` denies every client
/// write on `couriers` (`allow write: if false` — Cloud Function only),
/// matching `FirestoreStockCountRepository`/`FirestoreKitchenWorkItemRepository`'s
/// own identical precedent.
class FirestoreCourierRepository implements CourierRepository {
  FirestoreCourierRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Future<void> save(Courier courier) async {}

  @override
  Future<Courier?> findById(String courierId) async {
    final snap = await _firestore.collection('couriers').doc(courierId).get();
    if (!snap.exists) return null;
    return _mapCourier(courierId, snap.data()!);
  }

  @override
  Future<List<Courier>> findByBranchId(String branchId) async {
    final snap = await _firestore
        .collection('couriers')
        .where('branchId', isEqualTo: branchId)
        .get();
    return List.unmodifiable(
        [for (final doc in snap.docs) _mapCourier(doc.id, doc.data())]);
  }

  /// Live updates for [branchId]'s roster — the dispatch dialog's own read
  /// path (`CourierReturnFifo.sortAvailableByReturnTime` sorts the result
  /// client-side; no server-side FIFO index needed for a single branch's
  /// small roster).
  Stream<List<Courier>> watchByBranchId(String branchId) {
    return _firestore
        .collection('couriers')
        .where('branchId', isEqualTo: branchId)
        .snapshots()
        .map((snap) =>
            [for (final doc in snap.docs) _mapCourier(doc.id, doc.data())]);
  }

  Courier _mapCourier(String id, Map<String, dynamic> data) {
    return Courier(
      id: id,
      primaryBranchId: data['branchId'] as String,
      displayName: data['displayName'] as String,
      phoneNumber: data['phoneNumber'] as String,
      vehicleType: CourierVehicleType.values.byName(
          (data['vehicleType'] as String?) ?? CourierVehicleType.motorcycle.name),
      vehicleIdentifier: data['vehicleIdentifier'] as String? ?? '',
      capacity: (data['capacity'] as num?)?.toInt() ?? 1,
      status: CourierRegistryStatus.values.byName(
          (data['status'] as String?) ?? CourierRegistryStatus.active.name),
      registeredAt:
          (data['registeredAt'] as fs.Timestamp?)?.toDate() ?? DateTime(0),
      type: CourierType.values
          .byName((data['type'] as String?) ?? CourierType.internal.name),
      dispatchStatus: CourierStatus.values.byName(
          (data['dispatchStatus'] as String?) ?? CourierStatus.offline.name),
      returnedAt: (data['returnedAt'] as fs.Timestamp?)?.toDate(),
      activeOrderIds: (data['activeOrderIds'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }
}
