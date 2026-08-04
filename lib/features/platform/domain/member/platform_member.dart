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

  final DateTime createdAt;
  final int revision;

  bool get isActive => status == PlatformMemberStatus.active;

  PlatformMember copyWith({
    String? displayName,
    Set<PlatformRole>? roles,
    PlatformMemberStatus? status,
    DateTime? sessionsRevokedAt,
    bool clearSessionsRevokedAt = false,
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
      createdAt: createdAt,
      revision: revision,
    );
  }
}
