import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/translation_entry_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/localization/translation_entry.dart';
import '../../domain/localization/translation_status.dart';

/// Moves a [TranslationEntry]'s review lifecycle — admin-only
/// (`PosAuthorizedAction.manageLocalizationConfig`). Only
/// `needsReview`/`approved` are reachable through this use case;
/// `draft` is only ever set by `SetTranslationContent` (a content
/// change always resets review progress).
class ReviewTranslation {
  const ReviewTranslation({
    required PosAuthorizationPolicy authorizationPolicy,
    required TranslationEntryRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final TranslationEntryRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<TranslationEntry> call({
    required String translationEntryId,
    required TranslationStatus newStatus,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageLocalizationConfig;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(translationEntryId);
    if (existing == null) {
      throw UnknownAdminEntityViolation(
        entityName: 'TranslationEntry',
        id: translationEntryId,
      );
    }

    final updated = existing.copyWith(
      status: newStatus,
      translationRevision: existing.translationRevision,
      updatedAt: performedAt,
      updatedByStaffId: performedByStaffId,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '${existing.id}-audit-review-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.localizationConfigChanged,
      description: 'Translation "${existing.contentKey}" '
          '(${existing.language.name}) review status set to '
          '${newStatus.name}',
      targetEntityId: existing.id,
      previousStateName: existing.status.name,
      newStateName: newStatus.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
