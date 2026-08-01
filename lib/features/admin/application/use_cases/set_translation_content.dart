import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/translation_entry_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/localization/supported_language.dart';
import '../../domain/localization/translation_entry.dart';
import '../../domain/localization/translation_status.dart';
import '../identity/translation_entry_id_generator.dart';

/// Creates or overwrites a [TranslationEntry] — admin-only
/// (`PosAuthorizedAction.manageLocalizationConfig`). "Do not overwrite
/// manually edited translations automatically": a write with
/// `isMachineGenerated: true` is refused if the existing entry's
/// `isManuallyEdited` is already `true` — a human operator overwrites by
/// calling with `isMachineGenerated: false` instead, which is always
/// permitted and marks the entry `isManuallyEdited: true` going
/// forward. New content always lands in `TranslationStatus.draft` —
/// `ReviewTranslation` is the only path to `needsReview`/`approved`.
class SetTranslationContent {
  const SetTranslationContent({
    required PosAuthorizationPolicy authorizationPolicy,
    required TranslationEntryIdGenerator idGenerator,
    required TranslationEntryRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final TranslationEntryIdGenerator _idGenerator;
  final TranslationEntryRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<TranslationEntry> call({
    required String contentKey,
    required SupportedLanguage language,
    required String content,
    required bool isMachineGenerated,
    int? sourceContentRevision,
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

    final existing =
        await _repository.findByContentKeyAndLanguage(contentKey, language);
    if (existing != null && existing.isManuallyEdited && isMachineGenerated) {
      throw ManuallyEditedTranslationNotOverwritableViolation(
        contentKey: contentKey,
        languageName: language.name,
      );
    }

    final updated = existing == null
        ? TranslationEntry(
            id: _idGenerator.nextTranslationEntryId(),
            contentKey: contentKey,
            language: language,
            content: content,
            status: TranslationStatus.draft,
            isMachineGenerated: isMachineGenerated,
            isManuallyEdited: !isMachineGenerated,
            sourceContentRevision: sourceContentRevision ?? 1,
            translationRevision: 1,
            updatedAt: performedAt,
            updatedByStaffId: performedByStaffId,
          )
        : existing.copyWith(
            content: content,
            status: TranslationStatus.draft,
            isMachineGenerated: isMachineGenerated,
            isManuallyEdited: !isMachineGenerated || existing.isManuallyEdited,
            sourceContentRevision: sourceContentRevision,
            translationRevision: existing.translationRevision + 1,
            updatedAt: performedAt,
            updatedByStaffId: performedByStaffId,
          );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '${updated.id}-audit-content-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.localizationConfigChanged,
      description: 'Translation "$contentKey" (${language.name}) content '
          'updated (machine-generated: $isMachineGenerated)',
      targetEntityId: updated.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
