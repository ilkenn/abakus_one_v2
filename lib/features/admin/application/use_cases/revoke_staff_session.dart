import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/staff/staff_member.dart';

/// "Forced session revocation" — admin-only
/// (`PosAuthorizedAction.revokeStaffSession`). Sets
/// [StaffMember.sessionsRevokedAt] to [performedAt]; the next time
/// `StaffAuthRepository.refreshSession` runs for any session issued
/// before that timestamp, it returns `null` — this codebase has no
/// mechanism to reach into an already-running client and invalidate a
/// session live, so revocation takes effect on the next refresh, not
/// instantly (documented here, not silently assumed).
class RevokeStaffSession {
  const RevokeStaffSession({
    required PosAuthorizationPolicy authorizationPolicy,
    required StaffMemberRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StaffMemberRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<StaffMember> call({
    required String staffMemberId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.revokeStaffSession;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(staffMemberId);
    if (existing == null) {
      throw UnknownAdminEntityViolation(
        entityName: 'StaffMember',
        id: staffMemberId,
      );
    }

    final updated = existing.copyWith(
      sessionsRevokedAt: performedAt,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$staffMemberId-audit-session-revoked-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.staffSessionRevoked,
      description: 'Sessions revoked for $staffMemberId',
      targetEntityId: staffMemberId,
      timestamp: performedAt,
    ));

    return updated;
  }
}
