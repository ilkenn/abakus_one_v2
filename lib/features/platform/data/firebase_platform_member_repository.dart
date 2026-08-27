import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../../core/services/auth/platform_claims_sync_client.dart';
import '../domain/authorization/platform_role.dart';
import '../domain/member/platform_member.dart';
import '../domain/member/platform_member_status.dart';
import 'platform_member_repository.dart';

PlatformRole? _platformRoleFromWire(String value) {
  switch (value) {
    case 'platformAdministrator':
      return PlatformRole.platformAdministrator;
    case 'platformOwner':
      return PlatformRole.platformOwner;
    default:
      return null;
  }
}

PlatformMemberStatus _platformMemberStatusFromWire(String value) {
  switch (value) {
    case 'active':
      return PlatformMemberStatus.active;
    case 'suspended':
      return PlatformMemberStatus.suspended;
    case 'archived':
      return PlatformMemberStatus.archived;
    default:
      return PlatformMemberStatus.suspended;
  }
}

/// AP-2 final wiring — closes the real gap the AP-2 closure-correction
/// audit found: `FirebasePlatformAuthRepository.signIn` already called
/// `_platformMemberRepository.findByAuthUid(result.uid)` against a real
/// Firebase Auth result, but no Firestore-backed implementation of
/// [PlatformMemberRepository] existed anywhere in `lib/` — sign-in could
/// never actually succeed against a real backend. This closes that.
///
/// `platformMembers/{uid}`'s own Firestore rule (`isPlatformMember() &&
/// request.auth.uid == platformMemberId`) requires the caller's ID token
/// to already carry a `platformRole` custom claim before a read can
/// succeed — [PlatformClaimsSyncClient] is called first on every lookup
/// to resolve that chicken-and-egg (see its own doc comment). [findAll]
/// has no real backend capability behind it (a platform member may only
/// ever read their OWN doc, by design — no "list every platform member"
/// rule exists) and returns empty rather than throwing, since "I can't
/// list everyone" is not an error condition for this repository's real
/// callers (sign-in/session-refresh, both single-doc lookups). [save]
/// always throws — membership is granted only via the out-of-band
/// bootstrap script or `grantPlatformRole`/`revokePlatformRole`, never a
/// direct client write (`allow write: if false`).
class FirebasePlatformMemberRepository implements PlatformMemberRepository {
  FirebasePlatformMemberRepository({
    required PlatformClaimsSyncClient claimsSyncClient,
    fs.FirebaseFirestore? firestore,
  })  : _claimsSyncClient = claimsSyncClient,
        _providedFirestore = firestore;

  final PlatformClaimsSyncClient _claimsSyncClient;
  // Lazily resolved (never in the constructor) — mirrors
  // `FirebaseStaffMemberRepository`'s own `_callable` getter exactly, so
  // merely CONSTRUCTING this repository (e.g. a provider-resolution test
  // that never calls a method) never requires a real `Firebase.initializeApp()`.
  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Future<void> save(PlatformMember member) async {
    throw StateError(
      'Platform membership is granted only through the out-of-band '
      'bootstrap script or grantPlatformRole/revokePlatformRole — never a '
      'direct client write.',
    );
  }

  @override
  Future<PlatformMember?> findById(String platformMemberId) async {
    await _claimsSyncClient.syncAndRefresh();
    final doc = await _firestore
        .collection('platformMembers')
        .doc(platformMemberId)
        .get();
    if (!doc.exists) return null;
    return _mapMember(doc.id, doc.data()!);
  }

  @override
  Future<List<PlatformMember>> findAll() async => const [];

  @override
  Future<PlatformMember?> findByAuthUid(String authUid) => findById(authUid);

  PlatformMember _mapMember(String id, Map<String, dynamic> data) {
    final rawRoles = (data['roles'] as List? ?? []).cast<String>();
    final roles = <PlatformRole>{
      for (final r in rawRoles)
        if (_platformRoleFromWire(r) != null) _platformRoleFromWire(r)!,
    };
    return PlatformMember(
      id: id,
      displayName: data['displayName'] as String? ?? id,
      roles: roles,
      status:
          _platformMemberStatusFromWire(data['status'] as String? ?? 'active'),
      authUid: data['authUid'] as String? ?? id,
      createdAt:
          (data['createdAt'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
      revision: data['version'] as int? ?? 1,
    );
  }
}
