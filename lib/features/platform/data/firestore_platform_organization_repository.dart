import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../admin/data/organization_repository.dart';
import '../../admin/domain/organization/organization.dart';

/// AP-2 final wiring — the Platform Owner console's tenant picker. Reads
/// `organizations` unfiltered: `firestore.rules`'s own narrowly-scoped
/// exception (`canReadOrg(organizationId) || isPlatformMember()`, added
/// this pass) makes an unfiltered query provably safe for a platform
/// member specifically, since `isPlatformMember()` doesn't depend on
/// `resource.data` at all — every possible result document satisfies the
/// rule regardless of which organization it is. Read-only: [save] always
/// throws (`allow write: if false` — organizations are Cloud-Function-
/// only, this repository has no legitimate mutation path).
class FirestorePlatformOrganizationRepository
    implements OrganizationRepository {
  FirestorePlatformOrganizationRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  // Lazily resolved — see `FirebasePlatformMemberRepository`'s identical
  // doc comment for why construction alone must never require a real
  // `Firebase.initializeApp()`.
  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Future<void> save(Organization organization) async {
    throw StateError(
      'Organizations are Cloud-Function-only — the Platform Owner console '
      'has no legitimate mutation path for this collection.',
    );
  }

  @override
  Future<Organization?> findById(String organizationId) async {
    final doc =
        await _firestore.collection('organizations').doc(organizationId).get();
    if (!doc.exists) return null;
    return _mapOrganization(doc.id, doc.data()!);
  }

  @override
  Future<List<Organization>> findAll() async {
    final query = await _firestore.collection('organizations').get();
    return [
      for (final doc in query.docs) _mapOrganization(doc.id, doc.data()),
    ];
  }

  Organization _mapOrganization(String id, Map<String, dynamic> data) {
    return Organization(
      id: id,
      name: data['name'] as String? ?? id,
      createdAt:
          (data['createdAt'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
      revision: data['version'] as int? ?? 1,
    );
  }
}

class UnavailablePlatformOrganizationRepository
    implements OrganizationRepository {
  const UnavailablePlatformOrganizationRepository();

  Never _unavailable() =>
      throw StateError('Tenant directory is not available in this build.');

  @override
  Future<void> save(Organization organization) async => _unavailable();

  @override
  Future<Organization?> findById(String organizationId) async => _unavailable();

  @override
  Future<List<Organization>> findAll() async => _unavailable();
}
