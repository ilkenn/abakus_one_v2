import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/import_audit_entry_repository.dart';
import '../../data/import_job_repository.dart';
import '../../domain/import_approval.dart';
import '../../domain/import_audit_entry.dart';
import '../../domain/import_audit_event_type.dart';
import '../../domain/import_review_decision.dart';
import '../../domain/import_status.dart';

/// Records a reviewer's [ImportApproval] and transitions the
/// [ImportJob] to [ImportStatus.approved] (if at least one decision was
/// [ImportReviewOutcome.approved]) or [ImportStatus.rejected] (if every
/// decision was a rejection) — manager+
/// (`PosAuthorizedAction.manageSmartImport`). "The user must approve
/// before authoritative records are created" — this is that approval
/// step; `CommitImportDraft` refuses to run without it.
class ApproveImportDraft {
  const ApproveImportDraft({
    required PosAuthorizationPolicy authorizationPolicy,
    required ImportJobRepository jobRepository,
    required ImportAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _jobRepository = jobRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final ImportJobRepository _jobRepository;
  final ImportAuditEntryRepository _auditRepository;

  Future<ImportApproval> call({
    required String importJobId,
    required List<ImportReviewDecision> decisions,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final job = await _jobRepository.findById(importJobId);
    if (job == null) {
      throw UnknownImportEntityViolation(
        entityName: 'ImportJob',
        id: importJobId,
      );
    }
    if (job.status != ImportStatus.draftReady &&
        job.status != ImportStatus.underReview) {
      throw InvalidImportStatusTransitionViolation(
        fromStatusName: job.status.name,
        toStatusName: ImportStatus.approved.name,
      );
    }

    const action = PosAuthorizedAction.manageSmartImport;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: job.branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final anyApproved =
        decisions.any((d) => d.outcome == ImportReviewOutcome.approved);
    final newStatus =
        anyApproved ? ImportStatus.approved : ImportStatus.rejected;

    await _jobRepository.save(job.copyWith(
      status: newStatus,
      completedAt: newStatus == ImportStatus.rejected ? performedAt : null,
      revision: job.revision + 1,
    ));

    await _auditRepository.appendEvent(ImportAuditEntry(
      id: '$importJobId-audit-approval-${performedAt.microsecondsSinceEpoch}',
      branchId: job.branchId,
      actorId: performedByStaffId,
      type: anyApproved
          ? ImportAuditEventType.importApproved
          : ImportAuditEventType.importRejected,
      description:
          '${decisions.where((d) => d.outcome == ImportReviewOutcome.approved).length} '
          'approved, '
          '${decisions.where((d) => d.outcome == ImportReviewOutcome.rejected).length} '
          'rejected',
      targetEntityId: importJobId,
      timestamp: performedAt,
    ));

    return ImportApproval(
      importJobId: importJobId,
      approvedByStaffId: performedByStaffId,
      approvedAt: performedAt,
      decisions: decisions,
    );
  }
}
