import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/menu_label_audit_entry_repository.dart';
import '../../data/menu_label_suggestion_repository.dart';
import '../../domain/menu_label_audit_entry.dart';
import '../../domain/menu_label_audit_event_type.dart';
import '../../domain/menu_label_suggestion.dart';

/// A manager approves a system-generated [MenuLabelSuggestion] —
/// manager+ (`PosAuthorizedAction.manageNutrition`), Phase 7
/// (`docs/decisions.md` ADR-024). The only path that ever turns a
/// suggestion into an approved label.
class ApproveMenuLabelSuggestion {
  const ApproveMenuLabelSuggestion({
    required PosAuthorizationPolicy authorizationPolicy,
    required MenuLabelSuggestionRepository repository,
    required MenuLabelAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final MenuLabelSuggestionRepository _repository;
  final MenuLabelAuditEntryRepository _auditRepository;

  Future<MenuLabelSuggestion> call({
    required String organizationId,
    required String suggestionId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageNutrition;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final suggestion = await _repository.findById(suggestionId);
    if (suggestion == null) {
      throw UnknownMenuLabelEntityViolation(
        entityName: 'MenuLabelSuggestion',
        id: suggestionId,
      );
    }

    final updated = suggestion.copyWith(
      isApproved: true,
      approvedByStaffId: performedByStaffId,
      approvedAt: performedAt,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(MenuLabelAuditEntry(
      id: '${suggestion.id}-audit-approved',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: MenuLabelAuditEventType.suggestionApproved,
      description:
          'Menu label suggestion "${suggestion.labelType.name}" approved '
          'for recipe "${suggestion.recipeId}"',
      targetEntityId: suggestion.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
