import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/setup_audit_entry_repository.dart';
import '../../data/setup_template_application_snapshot_repository.dart';
import '../../data/setup_template_repository.dart';
import '../../domain/setup_audit_entry.dart';
import '../../domain/setup_audit_event_type.dart';
import '../../domain/setup_template_application_snapshot.dart';
import '../identity/setup_template_application_snapshot_id_generator.dart';

/// Records that a tenant adopted a [SetupTemplate] — manager+
/// (`PosAuthorizedAction.manageRestaurantSetup`). "Do not silently
/// activate products or recipes": this **only** creates the frozen
/// [SetupTemplateApplicationSnapshot] record — no `MenuCategory`/
/// `MenuProduct`/`Ingredient`/`Recipe` is ever created here. Turning a
/// suggestion into a real record is a separate, explicit admin action
/// (through Menu admin / Smart Import / Ingredient admin, each its own
/// approval step).
class ApplySetupTemplate {
  const ApplySetupTemplate({
    required PosAuthorizationPolicy authorizationPolicy,
    required SetupTemplateRepository templateRepository,
    required SetupTemplateApplicationSnapshotRepository snapshotRepository,
    required SetupTemplateApplicationSnapshotIdGenerator idGenerator,
    required SetupAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _templateRepository = templateRepository,
        _snapshotRepository = snapshotRepository,
        _idGenerator = idGenerator,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final SetupTemplateRepository _templateRepository;
  final SetupTemplateApplicationSnapshotRepository _snapshotRepository;
  final SetupTemplateApplicationSnapshotIdGenerator _idGenerator;
  final SetupAuditEntryRepository _auditRepository;

  Future<SetupTemplateApplicationSnapshot> call({
    required String templateId,
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageRestaurantSetup;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final template = await _templateRepository.findById(templateId);
    if (template == null) {
      throw UnknownSetupTemplateViolation(id: templateId);
    }

    final snapshot = SetupTemplateApplicationSnapshot(
      id: _idGenerator.nextSnapshotId(),
      templateId: template.id,
      templateRevisionApplied: template.revision,
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      categorySuggestions: List.unmodifiable(template.categorySuggestions),
      ingredientReferences: List.unmodifiable(template.ingredientReferences),
      modifierPatterns: List.unmodifiable(template.modifierPatterns),
      appliedByStaffId: performedByStaffId,
      appliedAt: performedAt,
    );
    await _snapshotRepository.save(snapshot);

    await _auditRepository.appendEvent(SetupAuditEntry(
      id: '${snapshot.id}-audit-applied',
      branchId: branchId,
      actorId: performedByStaffId,
      type: SetupAuditEventType.templateApplied,
      description:
          'Setup template "${template.id}" applied to branch "$branchId"',
      targetEntityId: snapshot.id,
      timestamp: performedAt,
    ));

    return snapshot;
  }
}
