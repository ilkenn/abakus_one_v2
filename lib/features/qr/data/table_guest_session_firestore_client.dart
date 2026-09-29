import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// The narrow slice of a `tableGuestSessions` document
/// [DineInCheckoutScreen] actually needs to re-verify a session is still
/// usable immediately before submitting an order — mirrors
/// `OrderFirestoreClient`'s own "narrow read-only slice behind an
/// interface" reasoning, applied to the one server-authoritative session
/// record instead of an order.
class TableGuestSessionSnapshot {
  final String status;
  final DateTime expiresAt;

  const TableGuestSessionSnapshot({
    required this.status,
    required this.expiresAt,
  });

  /// Mirrors `isTableGuestSessionActive`
  /// (`functions/src/tableGuestSessionConfig.ts`) exactly — the same
  /// `status == 'active' && expiresAt > now` boundary condition, checked
  /// client-side here only to give the customer a friendly Turkish error
  /// before ever attempting the write. The real authorization decision is
  /// always the Firestore Security Rule's own re-evaluation at write
  /// time — this check existing or not changes only the error message a
  /// stale session sees, never what it's allowed to do.
  bool get isActive => status == 'active' && DateTime.now().isBefore(expiresAt);
}

abstract interface class TableGuestSessionFirestoreClient {
  /// `null` if no `tableGuestSessions` document exists at [sessionId].
  Future<TableGuestSessionSnapshot?> findById(String sessionId);

  /// A live view of [findById] for [sessionId] — re-emits whenever the
  /// session document changes (e.g. staff closes the table before natural
  /// TTL expiry), so a UI can warn a browsing guest without waiting for
  /// them to reach checkout. `null` if the document doesn't exist (matches
  /// [findById]'s own contract).
  Stream<TableGuestSessionSnapshot?> watchById(String sessionId);
}

class DefaultTableGuestSessionFirestoreClient
    implements TableGuestSessionFirestoreClient {
  DefaultTableGuestSessionFirestoreClient({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  // Resolved lazily, not in the constructor — mirrors
  // `DefaultOrderFirestoreClient`'s exact reasoning:
  // `fs.FirebaseFirestore.instance` throws if no real Firebase app exists
  // yet, and a test proving provider wiring (not the real SDK) must not
  // crash at construction.
  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Future<TableGuestSessionSnapshot?> findById(String sessionId) async {
    final snapshot =
        await _firestore.collection('tableGuestSessions').doc(sessionId).get();
    if (!snapshot.exists) return null;
    return _parse(snapshot.data()!);
  }

  @override
  Stream<TableGuestSessionSnapshot?> watchById(String sessionId) {
    return _firestore
        .collection('tableGuestSessions')
        .doc(sessionId)
        .snapshots()
        .map((snapshot) => snapshot.exists ? _parse(snapshot.data()!) : null);
  }

  TableGuestSessionSnapshot _parse(Map<String, dynamic> data) {
    final rawExpiresAt = data['expiresAt'];
    final expiresAt = rawExpiresAt is fs.Timestamp
        ? rawExpiresAt.toDate()
        : DateTime.parse(rawExpiresAt as String);

    return TableGuestSessionSnapshot(
      status: data['status'] as String,
      expiresAt: expiresAt,
    );
  }
}
