import '../../../../core/errors/business_rule_violation.dart';
import '../../../inventory/domain/inventory_unit.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/nutrition_audit_entry_repository.dart';
import '../../data/nutrition_reference_entry_repository.dart';
import '../../domain/nutrition_audit_entry.dart';
import '../../domain/nutrition_audit_event_type.dart';
import '../../domain/nutrition_confidence.dart';
import '../../domain/nutrition_data_source_type.dart';
import '../../domain/nutrition_reference_entry.dart';
import '../../domain/nutrition_value_set.dart';
import '../identity/nutrition_reference_entry_id_generator.dart';

/// Creates or updates (upserts by `ingredientId`) one ingredient's
/// [NutritionReferenceEntry] — manager+
/// (`PosAuthorizedAction.manageNutrition`), Phase 7
/// (`docs/decisions.md` ADR-024). A [NutritionDataSourceType.manual]
/// entry requires a non-empty [reason] — "manual values require
/// actor+reason+audit" — and defaults to
/// [NutritionConfidence.low] unless the caller explicitly overrides it
/// (an unreviewed manual entry is never presented as high-confidence).
/// Never fabricates a value: only the fields the caller actually
/// supplies in [values] are stored; everything else stays `null`.
class SetNutritionReferenceEntry {
  const SetNutritionReferenceEntry({
    required PosAuthorizationPolicy authorizationPolicy,
    required NutritionReferenceEntryIdGenerator idGenerator,
    required NutritionReferenceEntryRepository repository,
    required NutritionAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final NutritionReferenceEntryIdGenerator _idGenerator;
  final NutritionReferenceEntryRepository _repository;
  final NutritionAuditEntryRepository _auditRepository;

  Future<NutritionReferenceEntry> call({
    required String organizationId,
    required String ingredientId,
    required NutritionValueSet values,
    required InventoryUnit referenceUnit,
    required NutritionDataSourceType sourceType,
    String? sourceName,
    String? sourceRecordId,
    String? sourceRevision,
    DateTime? sourceDate,
    NutritionConfidence? confidence,
    String? overrideReason,
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

    final isManual = sourceType == NutritionDataSourceType.manual;
    if (isManual && (overrideReason == null || overrideReason.trim().isEmpty)) {
      throw const NutritionOverrideReasonRequiredViolation();
    }

    final existing = await _repository.findByIngredientId(ingredientId);
    final entry = NutritionReferenceEntry(
      id: existing?.id ?? _idGenerator.nextNutritionReferenceEntryId(),
      organizationId: organizationId,
      ingredientId: ingredientId,
      values: values,
      referenceUnit: referenceUnit,
      sourceType: sourceType,
      sourceName: sourceName,
      sourceRecordId: sourceRecordId,
      sourceRevision: sourceRevision,
      sourceDate: sourceDate,
      confidence: confidence ??
          (isManual ? NutritionConfidence.low : NutritionConfidence.medium),
      isManuallyOverridden: isManual,
      reviewedByStaffId: existing?.reviewedByStaffId,
      reviewedAt: existing?.reviewedAt,
      createdAt: existing?.createdAt ?? performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(entry);

    await _auditRepository.appendEvent(NutritionAuditEntry(
      id: '${entry.id}-audit-set-${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: NutritionAuditEventType.entrySet,
      description: isManual
          ? 'Nutrition reference for "$ingredientId" manually set: '
              '$overrideReason'
          : 'Nutrition reference for "$ingredientId" set from '
              '${sourceName ?? 'external provider'}',
      targetEntityId: entry.id,
      timestamp: performedAt,
    ));

    return entry;
  }
}
