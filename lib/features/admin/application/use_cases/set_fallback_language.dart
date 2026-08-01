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

/// Sets the fallback [SupportedLanguage] for a `LocalizationConfig` —
/// admin-only (`PosAuthorizedAction.manageLocalizationConfig`). The
/// target language must already be enabled for the scope — use
/// `SetLanguageEnabled` first.
class SetFallbackLanguage {
  const SetFallbackLanguage({
    required PosAuthorizationPolicy authorizationPolicy,
    required LocalizationConfigRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final LocalizationConfigRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<LocalizationConfig> call({
    required LocalizationScopeType scopeType,
    required String scopeId,
    required SupportedLanguage language,
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

    final existing = await _repository.findByScope(scopeType, scopeId);
    if (existing == null || !existing.enabledLanguages.contains(language)) {
      throw FallbackLanguageMustBeEnabledViolation(languageName: language.name);
    }

    final updated = existing.copyWith(
      fallbackLanguage: language,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      branchId: scopeType == LocalizationScopeType.branch ? scopeId : null,
      id: '${updated.id}-audit-fallback-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.localizationConfigChanged,
      description: 'Fallback language set to ${language.name} for '
          '${scopeType.name}:$scopeId',
      targetEntityId: updated.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
