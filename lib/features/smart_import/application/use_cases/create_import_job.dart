import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/import_audit_entry_repository.dart';
import '../../data/import_job_repository.dart';
import '../../domain/import_audit_entry.dart';
import '../../domain/import_audit_event_type.dart';
import '../../domain/import_job.dart';
import '../../domain/import_source.dart';
import '../identity/import_job_id_generator.dart';

/// Starts a new [ImportJob] — manager+
/// (`PosAuthorizedAction.manageSmartImport`). Records intent only —
/// parsing happens as an explicit, separate next step
/// (`ParseImportSource`), never inline here.
class CreateImportJob {
  const CreateImportJob({
    required PosAuthorizationPolicy authorizationPolicy,
    required ImportJobIdGenerator idGenerator,
    required ImportJobRepository repository,
    required ImportAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final ImportJobIdGenerator _idGenerator;
  final ImportJobRepository _repository;
  final ImportAuditEntryRepository _auditRepository;

  Future<ImportJob> call({
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required ImportSource source,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageSmartImport;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final job = ImportJob(
      id: _idGenerator.nextImportJobId(),
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      source: source,
      createdByStaffId: performedByStaffId,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(job);

    await _auditRepository.appendEvent(ImportAuditEntry(
      id: '${job.id}-audit-created',
      branchId: branchId,
      actorId: performedByStaffId,
      type: ImportAuditEventType.importCreated,
      description: 'Import job created (${source.type.name})',
      targetEntityId: job.id,
      timestamp: performedAt,
    ));

    return job;
  }
}
