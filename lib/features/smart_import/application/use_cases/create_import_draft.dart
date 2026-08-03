import '../../../../core/errors/business_rule_violation.dart';
import '../../data/import_audit_entry_repository.dart';
import '../../data/import_draft_repository.dart';
import '../../data/import_job_repository.dart';
import '../../domain/import_audit_entry.dart';
import '../../domain/import_audit_event_type.dart';
import '../../domain/import_draft.dart';
import '../../domain/import_status.dart';
import '../../domain/parsed_menu.dart';
import '../identity/import_draft_id_generator.dart';

/// Persists a normalized+analyzed [ParsedMenu] as the reviewable
/// [ImportDraft] — Phase 7 (`docs/decisions.md` ADR-024). Transitions
/// the job to [ImportStatus.draftReady]. Re-running this for the same
/// job (e.g. after a re-parse) creates a new draft revision rather than
/// silently discarding the prior one — `ImportDraftRepository
/// .findByImportJobId` always returns the current one.
class CreateImportDraft {
  const CreateImportDraft({
    required ImportJobRepository jobRepository,
    required ImportDraftRepository draftRepository,
    required ImportDraftIdGenerator idGenerator,
    required ImportAuditEntryRepository auditRepository,
  })  : _jobRepository = jobRepository,
        _draftRepository = draftRepository,
        _idGenerator = idGenerator,
        _auditRepository = auditRepository;

  final ImportJobRepository _jobRepository;
  final ImportDraftRepository _draftRepository;
  final ImportDraftIdGenerator _idGenerator;
  final ImportAuditEntryRepository _auditRepository;

  Future<ImportDraft> call({
    required String importJobId,
    required ParsedMenu parsedMenu,
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
    if (job.status != ImportStatus.parsed &&
        job.status != ImportStatus.draftReady) {
      throw InvalidImportStatusTransitionViolation(
        fromStatusName: job.status.name,
        toStatusName: ImportStatus.draftReady.name,
      );
    }

    final existing = await _draftRepository.findByImportJobId(importJobId);
    final draft = existing == null
        ? ImportDraft(
            id: _idGenerator.nextImportDraftId(),
            importJobId: importJobId,
            parsedMenu: parsedMenu,
            createdAt: performedAt,
            revision: 1,
          )
        : existing.copyWith(
            parsedMenu: parsedMenu, revision: existing.revision + 1);
    await _draftRepository.save(draft);

    await _jobRepository.save(job.copyWith(
      status: ImportStatus.draftReady,
      revision: job.revision + 1,
    ));

    await _auditRepository.appendEvent(ImportAuditEntry(
      id: '${draft.id}-audit-draft-${performedAt.microsecondsSinceEpoch}',
      branchId: job.branchId,
      actorId: performedByStaffId,
      type: ImportAuditEventType.draftEdited,
      description: 'Draft ready: ${parsedMenu.products.length} products, '
          '${parsedMenu.issues.length} issues',
      targetEntityId: importJobId,
      timestamp: performedAt,
    ));

    return draft;
  }
}
