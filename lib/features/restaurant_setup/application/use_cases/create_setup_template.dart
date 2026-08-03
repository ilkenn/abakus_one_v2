import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/setup_audit_entry_repository.dart';
import '../../data/setup_template_repository.dart';
import '../../domain/setup_audit_entry.dart';
import '../../domain/setup_audit_event_type.dart';
import '../../domain/setup_template.dart';
import '../../domain/setup_template_category.dart';
import '../../domain/setup_template_content.dart';
import '../identity/setup_template_id_generator.dart';

/// Creates a [SetupTemplate] — publishing a **public** (platform-owned)
/// template requires `PosAuthorizedAction.manageOrganization`
/// (admin-only, the same tier platform-wide structural decisions
/// already require); creating a **private** (tenant-owned) template
/// requires only `PosAuthorizedAction.manageRestaurantSetup`
/// (manager+). Which tier applies is picked by [isPublic] — the same
/// "action selection enforces the sensitive-vs-routine distinction"
/// pattern `AssignStaffRole` established for admin-role grants (Phase
/// 6C).
class CreateSetupTemplate {
  const CreateSetupTemplate({
    required PosAuthorizationPolicy authorizationPolicy,
    required SetupTemplateIdGenerator idGenerator,
    required SetupTemplateRepository repository,
    required SetupAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final SetupTemplateIdGenerator _idGenerator;
  final SetupTemplateRepository _repository;
  final SetupAuditEntryRepository _auditRepository;

  Future<SetupTemplate> call({
    required SetupTemplateCategory category,
    required String name,
    List<TemplateCategorySuggestion> categorySuggestions = const [],
    List<TemplateIngredientReference> ingredientReferences = const [],
    List<TemplateModifierPattern> modifierPatterns = const [],
    List<String> measurementUnitHints = const [],
    List<String> recipePlaceholderNames = const [],
    List<String> stockCardSuggestionNames = const [],
    List<String> allergenHints = const [],
    String? nutritionDataReferenceNote,
    required bool isPublic,
    String? ownerOrganizationId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    if (isPublic == (ownerOrganizationId != null)) {
      throw const InvalidSetupTemplateOwnershipViolation();
    }

    final action = isPublic
        ? PosAuthorizedAction.manageOrganization
        : PosAuthorizedAction.manageRestaurantSetup;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final template = SetupTemplate(
      id: _idGenerator.nextSetupTemplateId(),
      category: category,
      name: name,
      categorySuggestions: categorySuggestions,
      ingredientReferences: ingredientReferences,
      modifierPatterns: modifierPatterns,
      measurementUnitHints: measurementUnitHints,
      recipePlaceholderNames: recipePlaceholderNames,
      stockCardSuggestionNames: stockCardSuggestionNames,
      allergenHints: allergenHints,
      nutritionDataReferenceNote: nutritionDataReferenceNote,
      isPublic: isPublic,
      ownerOrganizationId: ownerOrganizationId,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(template);

    await _auditRepository.appendEvent(SetupAuditEntry(
      id: '${template.id}-audit-created',
      branchId: null,
      actorId: performedByStaffId,
      type: SetupAuditEventType.templateCreated,
      description:
          'Setup template "$name" created (${isPublic ? 'public' : 'private'})',
      targetEntityId: template.id,
      timestamp: performedAt,
    ));

    return template;
  }
}
