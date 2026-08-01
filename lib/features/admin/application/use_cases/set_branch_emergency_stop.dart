import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/branch_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/organization/branch.dart';

/// Triggers or clears a whole-branch emergency operational stop —
/// admin-only (`PosAuthorizedAction.branchEmergencyStop`), the most
/// sensitive/irreversible-feeling admin action, so it is deliberately
/// admin-tier, not manager-tier (unlike `manageBranch`'s day-to-day
/// edits). Distinct from `PosAuthorizedAction.emergencyChannelClosure`
/// (Phase 3, per-channel/per-order-flow) — this stops the entire branch.
class SetBranchEmergencyStop {
  const SetBranchEmergencyStop({
    required PosAuthorizationPolicy authorizationPolicy,
    required BranchRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final BranchRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<Branch> call({
    required String branchId,
    required bool stopped,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.branchEmergencyStop;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(branchId);
    if (existing == null) {
      throw UnknownAdminEntityViolation(entityName: 'Branch', id: branchId);
    }

    final updated = existing.copyWith(
      emergencyStopped: stopped,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$branchId-audit-emergency-${performedAt.microsecondsSinceEpoch}',
      branchId: branchId,
      actorId: performedByStaffId,
      type: AdminAuditEventType.branchEmergencyStopTriggered,
      description: stopped
          ? 'Branch emergency stop triggered'
          : 'Branch emergency stop cleared',
      targetEntityId: branchId,
      previousStateName: existing.emergencyStopped.toString(),
      newStateName: stopped.toString(),
      timestamp: performedAt,
    ));

    return updated;
  }
}
