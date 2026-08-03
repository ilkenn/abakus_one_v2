import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/nutrition_audit_entry_repository.dart';
import '../../data/nutrition_reference_entry_repository.dart';
import '../../domain/nutrition_audit_entry.dart';
import '../../domain/nutrition_audit_event_type.dart';
import '../../domain/nutrition_confidence.dart';
import '../../domain/nutrition_reference_entry.dart';

/// Records that a manager has reviewed one [NutritionReferenceEntry],
/// raising its [NutritionConfidence] — manager+
/// (`PosAuthorizedAction.manageNutrition`), Phase 7
/// (`docs/decisions.md` ADR-024). Distinguishes "calculated estimate"
/// from "verified value" per the brief's own requirement — an
/// unreviewed manual entry stays at [NutritionConfidence.low] until
/// this runs.
class ReviewNutritionReferenceEntry {
  const ReviewNutritionReferenceEntry({
    required PosAuthorizationPolicy authorizationPolicy,
    required NutritionReferenceEntryRepository repository,
    required NutritionAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final NutritionReferenceEntryRepository _repository;
  final NutritionAuditEntryRepository _auditRepository;

  Future<NutritionReferenceEntry> call({
    required String entryId,
    required NutritionConfidence confidence,
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

    final entry = await _repository.findById(entryId);
    if (entry == null) {
      throw UnknownNutritionEntityViolation(
        entityName: 'NutritionReferenceEntry',
        id: entryId,
      );
    }

    final updated = entry.copyWith(
      confidence: confidence,
      reviewedByStaffId: performedByStaffId,
      reviewedAt: performedAt,
      revision: entry.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(NutritionAuditEntry(
      id: '${entry.id}-audit-reviewed-${performedAt.microsecondsSinceEpoch}',
      organizationId: entry.organizationId,
      actorId: performedByStaffId,
      type: NutritionAuditEventType.entryReviewed,
      description: 'Nutrition reference for "${entry.ingredientId}" reviewed, '
          'confidence set to ${confidence.name}',
      targetEntityId: entry.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
