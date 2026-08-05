import '../authorization/platform_role.dart';
import 'platform_member_status.dart';

/// A registered platform-level account — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors `StaffMember`'s registry
/// shape, but deliberately carries **no branch/restaurant/organization
/// access field of any kind** — a platform member is global by
/// construction, the same reasoning `PlatformActorSession` already
/// documents.
class PlatformMember {
  const PlatformMember({
    required this.id,
    required this.displayName,
    this.roles = const {},
    this.status = PlatformMemberStatus.active,
    this.sessionsRevokedAt,
    this.authUid,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String displayName;
  final Set<PlatformRole> roles;
  final PlatformMemberStatus status;

  /// Mirrors `StaffMember.sessionsRevokedAt`'s forced-revocation
  /// contract.
  final DateTime? sessionsRevokedAt;

  /// The linked Firebase Auth UID — Sprint 9C (`docs/decisions.md`
  /// ADR-026). Mirrors `StaffMember.authUid` exactly; see its own doc
  /// comment.
  final String? authUid;

  final DateTime createdAt;
  final int revision;

  bool get isActive => status == PlatformMemberStatus.active;

  PlatformMember copyWith({
    String? displayName,
    Set<PlatformRole>? roles,
    PlatformMemberStatus? status,
    DateTime? sessionsRevokedAt,
    bool clearSessionsRevokedAt = false,
    String? authUid,
    required int revision,
  }) {
    return PlatformMember(
      id: id,
      displayName: displayName ?? this.displayName,
      roles: roles ?? this.roles,
      status: status ?? this.status,
      sessionsRevokedAt: clearSessionsRevokedAt
          ? null
          : (sessionsRevokedAt ?? this.sessionsRevokedAt),
      authUid: authUid ?? this.authUid,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
