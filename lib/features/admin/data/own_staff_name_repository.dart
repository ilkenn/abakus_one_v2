import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// ADR-085 stage 3 — the signed-in person's own name for the panel header.
/// Reads their own membership (`memberships/{org}_{uid}`, which the rules
/// let only that person read) for the first/last name "Personel Ekle"
/// stored; falls back to the account's display name. `null` when neither
/// is known — the header then shows the role alone.
abstract interface class OwnStaffNameRepository {
  Future<String?> ownName({
    required String organizationId,
    required String uid,
  });
}

class FirebaseOwnStaffNameRepository implements OwnStaffNameRepository {
  const FirebaseOwnStaffNameRepository();

  @override
  Future<String?> ownName({
    required String organizationId,
    required String uid,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('memberships')
          .doc('${organizationId}_$uid')
          .get();
      final data = snapshot.data();
      final name = [data?['firstName'], data?['lastName']]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(' ');
      if (name.isNotEmpty) return name;
    } on FirebaseException {
      // Fall through to the account name.
    }
    final displayName = fb.FirebaseAuth.instance.currentUser?.displayName;
    final trimmed = displayName?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Selected whenever Firebase isn't ready (tests, offline bootstrap).
class UnavailableOwnStaffNameRepository implements OwnStaffNameRepository {
  const UnavailableOwnStaffNameRepository();

  @override
  Future<String?> ownName({
    required String organizationId,
    required String uid,
  }) async =>
      null;
}
