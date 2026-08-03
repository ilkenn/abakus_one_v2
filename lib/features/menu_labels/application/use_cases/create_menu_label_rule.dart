import '../../../../core/errors/business_rule_violation.dart';
import '../../../allergens/domain/allergen_type.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/menu_label_audit_entry_repository.dart';
import '../../data/menu_label_rule_repository.dart';
import '../../domain/menu_label_audit_entry.dart';
import '../../domain/menu_label_audit_event_type.dart';
import '../../domain/menu_label_rule.dart';
import '../../domain/menu_label_type.dart';
import '../identity/menu_label_rule_id_generator.dart';

/// Creates a new, versioned [MenuLabelRule] — manager+
/// (`PosAuthorizedAction.manageNutrition`, reused rather than adding
/// a menu-label-specific action for the same "configures an automatic
/// label rule" act), Phase 7 (`docs/decisions.md` ADR-024). Never
/// mutates a prior rule version for the same [MenuLabelType] — "label
/// rule versions stored" — the version number is derived from how
/// many rules already exist for that label type.
class CreateMenuLabelRule {
  const CreateMenuLabelRule({
    required PosAuthorizationPolicy authorizationPolicy,
    required MenuLabelRuleIdGenerator idGenerator,
    required MenuLabelRuleRepository repository,
    required MenuLabelAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final MenuLabelRuleIdGenerator _idGenerator;
  final MenuLabelRuleRepository _repository;
  final MenuLabelAuditEntryRepository _auditRepository;

  Future<MenuLabelRule> call({
    required String organizationId,
    required MenuLabelType labelType,
    required String description,
    int? thresholdMilligramsOrKcal,
    AllergenType? freeFromAllergenType,
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

    final existing =
        await _repository.findActiveByLabelType(organizationId, labelType);
    final rule = MenuLabelRule(
      id: _idGenerator.nextMenuLabelRuleId(),
      organizationId: organizationId,
      labelType: labelType,
      ruleVersion: existing.length + 1,
      description: description,
      thresholdMilligramsOrKcal: thresholdMilligramsOrKcal,
      freeFromAllergenType: freeFromAllergenType,
      isActive: true,
      createdAt: performedAt,
      createdByStaffId: performedByStaffId,
    );
    await _repository.save(rule);

    await _auditRepository.appendEvent(MenuLabelAuditEntry(
      id: '${rule.id}-audit-created',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: MenuLabelAuditEventType.ruleCreated,
      description:
          'Menu label rule for "${labelType.name}" created (v${rule.ruleVersion})',
      targetEntityId: rule.id,
      timestamp: performedAt,
    ));

    return rule;
  }
}
