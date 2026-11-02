import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../../shared/models/customer_photo.dart';
import '../../../shared/models/customer_photo_status.dart';
import 'customer_photo_firestore_mapper.dart';

abstract interface class CustomerPhotoRepository {
  Future<void> save(CustomerPhoto photo);
  Future<CustomerPhoto?> findById(String photoId);
  Future<List<CustomerPhoto>> findByCustomerId(String customerId);

  /// Every photo currently `pendingReview`/`underReview` for
  /// [organizationId] — the moderation queue's own read path.
  /// [organizationId] is required: without it, Cloud Firestore can't
  /// statically prove every possible result of a `status`-only query
  /// satisfies `customerPhotos`' `firestore.rules` read rule
  /// (`isOwner(resource.data.customerId) ||
  /// isOrgMember(resource.data.organizationId)`) and rejects the whole
  /// query outright — the same class of regression found and fixed in
  /// `FirestoreKitchenTicketRepository`/`FirestoreKitchenWorkItemRepository`/
  /// `OrderFirestoreClient` on 2026-10-27; applied here from the start.
  Future<List<CustomerPhoto>> findPendingReview({
    required String organizationId,
  });
}

class InMemoryCustomerPhotoRepository implements CustomerPhotoRepository {
  final Map<String, CustomerPhoto> _byId = {};

  @override
  Future<void> save(CustomerPhoto photo) async => _byId[photo.id] = photo;

  @override
  Future<CustomerPhoto?> findById(String photoId) async => _byId[photoId];

  @override
  Future<List<CustomerPhoto>> findByCustomerId(String customerId) async {
    return List.unmodifiable(
      _byId.values.where((p) => p.customerId == customerId),
    );
  }

  // No multi-tenant data in dev/test — organizationId accepted, for
  // interface parity with the real implementation, and ignored (mirrors
  // `InMemoryKitchenTicketRepository`'s identical parameter).
  @override
  Future<List<CustomerPhoto>> findPendingReview({
    required String organizationId,
  }) async {
    return List.unmodifiable(
      _byId.values.where((p) =>
          p.status == CustomerPhotoStatus.pendingReview ||
          p.status == CustomerPhotoStatus.underReview),
    );
  }
}

/// The real, Firestore-backed [CustomerPhotoRepository] — read-only by
/// design. [save] is an intentional, documented no-op: `firestore.rules`
/// denies every client write to `customerPhotos` (`allow write: if
/// false`) — the real `moderateCustomerPhoto` Cloud Function
/// (`CustomerPhotoModerationGateway`) is the only writer, mirroring
/// `FirestoreKitchenTicketRepository`/`FirestoreKitchenWorkItemRepository`'s
/// identical "reads here, mutations through a gateway" split.
class FirestoreCustomerPhotoRepository implements CustomerPhotoRepository {
  FirestoreCustomerPhotoRepository({fs.FirebaseFirestore? firestore})
      : _firestore = firestore ?? fs.FirebaseFirestore.instance;

  final fs.FirebaseFirestore _firestore;

  fs.CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('customerPhotos');

  @override
  Future<void> save(CustomerPhoto photo) async {
    // Deliberate no-op — see class doc comment.
  }

  @override
  Future<CustomerPhoto?> findById(String photoId) async {
    final doc = await _collection.doc(photoId).get();
    final data = doc.data();
    if (data == null) return null;
    return CustomerPhotoFirestoreMapper.fromFirestore(doc.id, data);
  }

  @override
  Future<List<CustomerPhoto>> findByCustomerId(String customerId) async {
    final snapshot =
        await _collection.where('customerId', isEqualTo: customerId).get();
    return [
      for (final doc in snapshot.docs)
        CustomerPhotoFirestoreMapper.fromFirestore(doc.id, doc.data()),
    ];
  }

  @override
  Future<List<CustomerPhoto>> findPendingReview({
    required String organizationId,
  }) async {
    final snapshot = await _collection
        .where('organizationId', isEqualTo: organizationId)
        .where('status', whereIn: ['pendingReview', 'underReview']).get();
    return [
      for (final doc in snapshot.docs)
        CustomerPhotoFirestoreMapper.fromFirestore(doc.id, doc.data()),
    ];
  }
}
