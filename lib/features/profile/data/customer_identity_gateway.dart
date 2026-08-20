import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../domain/models/customer_identity.dart';

/// P.4.3B — the customer-side read of their own canonical
/// `customers/{uid}` document. Mirrors
/// `FirebaseCustomerPhotoGateway.watchGallery`'s established shape (a
/// direct client `.snapshots()` Firestore read against a collection whose
/// rule already permits it — here, `customers/{uid}`'s existing
/// owner-only `allow read: if isSignedIn() && request.auth.uid == uid`,
/// unchanged by this feature). Read-only: nothing in this file ever
/// writes `customers/{uid}` — that stays exclusively
/// `completeCustomerProfile` (Admin SDK).
abstract interface class CustomerIdentityGateway {
  /// `null` if the document doesn't exist yet (e.g. a caller reached this
  /// before "Profilini Tamamla" ever ran) — never thrown for that case.
  Stream<CustomerIdentity?> watchOwnIdentity({required String uid});
}

class FirebaseCustomerIdentityGateway implements CustomerIdentityGateway {
  FirebaseCustomerIdentityGateway({fs.FirebaseFirestore? firestore})
      : _firestore = firestore ?? fs.FirebaseFirestore.instance;

  final fs.FirebaseFirestore _firestore;

  @override
  Stream<CustomerIdentity?> watchOwnIdentity({required String uid}) {
    return _firestore.collection('customers').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return _mapIdentity(snap.data()!);
    });
  }

  /// Defensive by design — a missing/malformed field never throws (which
  /// would surface as a crashed hero for the customer); it degrades to an
  /// empty string / [CustomerOccupationStatus.unknown] instead, matching
  /// this codebase's established "never fabricate, never crash on display
  /// data" discipline (`CustomerPhoto`'s own mapping follows the same
  /// rule).
  CustomerIdentity _mapIdentity(Map<String, dynamic> data) {
    return CustomerIdentity(
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      occupationStatus:
          parseCustomerOccupationStatus(data['occupationStatus'] as String?),
      workplaceName: data['workplaceName'] as String?,
      educationalInstitutionName: data['educationalInstitutionName'] as String?,
    );
  }
}
