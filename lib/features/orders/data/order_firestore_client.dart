import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// The narrow slice of Firestore's API [FirestoreCanonicalOrderRepository]
/// actually needs, behind an interface — mirrors `FirebaseAuthClient`/
/// `CrashlyticsClient`'s exact injectable-wrapper reasoning (Sprints
/// 9A/9C): the real `cloud_firestore` SDK is unavailable under
/// `flutter test` (it's backed by a platform channel), so every real
/// consumer wraps a narrow, mockable interface instead of calling
/// `FirebaseFirestore.instance` directly.
abstract interface class OrderFirestoreClient {
  Future<void> setOrder(String orderId, Map<String, dynamic> data);

  /// `null` if no document exists at [orderId].
  Future<Map<String, dynamic>?> getOrder(String orderId);

  Future<List<Map<String, dynamic>>> queryOrdersByCustomerId(String customerId);

  Future<List<Map<String, dynamic>>> getAllOrders();
}

/// The real implementation, wrapping the `orders` collection —
/// `docs/firestore_data_model.md`/`firestore.rules` define this
/// collection's shape; [OrderFirestoreMapper] is what actually produces/
/// consumes the maps this class passes through unchanged.
class DefaultOrderFirestoreClient implements OrderFirestoreClient {
  DefaultOrderFirestoreClient({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  // Resolved lazily, not in the constructor — mirrors
  // `DefaultFirebaseAuthClient`'s exact reasoning
  // (`features/auth/data/repositories/firebase_auth_client.dart`):
  // `fs.FirebaseFirestore.instance` throws if no real Firebase app exists
  // yet, and a test proving provider *wiring* (not the real SDK) must not
  // crash at construction.
  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  fs.CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('orders');

  @override
  Future<void> setOrder(String orderId, Map<String, dynamic> data) {
    return _collection.doc(orderId).set(data);
  }

  @override
  Future<Map<String, dynamic>?> getOrder(String orderId) async {
    final snapshot = await _collection.doc(orderId).get();
    return snapshot.data();
  }

  @override
  Future<List<Map<String, dynamic>>> queryOrdersByCustomerId(
      String customerId) async {
    final snapshot =
        await _collection.where('customerId', isEqualTo: customerId).get();
    return [for (final doc in snapshot.docs) doc.data()];
  }

  @override
  Future<List<Map<String, dynamic>>> getAllOrders() async {
    final snapshot = await _collection.get();
    return [for (final doc in snapshot.docs) doc.data()];
  }
}
