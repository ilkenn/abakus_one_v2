import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/localization_config_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/localization/localization_config.dart';
import '../../domain/localization/localization_scope_type.dart';
import '../../domain/localization/supported_language.dart';
import '../identity/localization_config_id_generator.dart';

/// Enables or disables a [SupportedLanguage] for one
/// `(LocalizationScopeType, scopeId)` pair — admin-only
/// (`PosAuthorizedAction.manageLocalizationConfig`). Creates a default
/// `LocalizationConfig` (`{tr}` enabled, `tr` fallback) the first time a
/// scope is touched — callers never need a separate "initialize scope"
/// step.
///
/// [SupportedLanguage.master] (`tr`) can never be disabled. A language
/// currently set as the scope's fallback cannot be disabled either —
/// change the fallback first via `SetFallbackLanguage`.
class SetLanguageEnabled {
  const SetLanguageEnabled({
    required PosAuthorizationPolicy authorizationPolicy,
    required LocalizationConfigIdGenerator idGenerator,
    required LocalizationConfigRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final LocalizationConfigIdGenerator _idGenerator;
  final LocalizationConfigRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<LocalizationConfig> call({
    required LocalizationScopeType scopeType,
    required String scopeId,
    required SupportedLanguage language,
    required bool enabled,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageLocalizationConfig;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: scopeType == LocalizationScopeType.branch
          ? {kBranchIdAuthorizationContextKey: scopeId}
          : const {},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (!enabled && language == SupportedLanguage.master) {
      throw const MasterLanguageCannotBeDisabledViolation();
    }

    final existing = await _repository.findByScope(scopeType, scopeId);
    final current = existing ??
        LocalizationConfig(
          id: _idGenerator.nextLocalizationConfigId(),
          scopeType: scopeType,
          scopeId: scopeId,
          createdAt: performedAt,
          revision: 1,
        );

    if (!enabled && language == current.fallbackLanguage) {
      throw FallbackLanguageCannotBeDisabledViolation(
        languageName: language.name,
      );
    }

    final updatedLanguages = {...current.enabledLanguages};
    if (enabled) {
      updatedLanguages.add(language);
    } else {
      updatedLanguages.remove(language);
    }

    final updated = current.copyWith(
      enabledLanguages: updatedLanguages,
      revision: existing == null ? current.revision : current.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      branchId: scopeType == LocalizationScopeType.branch ? scopeId : null,
      id: '${updated.id}-audit-lang-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.localizationConfigChanged,
      description: '${language.name} ${enabled ? 'enabled' : 'disabled'} for '
          '${scopeType.name}:$scopeId',
      targetEntityId: updated.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
