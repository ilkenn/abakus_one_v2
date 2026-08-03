import '../../inventory/domain/inventory_unit.dart';
import 'nutrition_confidence.dart';
import 'nutrition_data_source_type.dart';
import 'nutrition_value_set.dart';

/// One ingredient's standardized nutrition reference — Phase 7
/// (`docs/decisions.md` ADR-024). Organization + `ingredientId`
/// scoped, one entry per ingredient (upserted, see
/// `SetNutritionReferenceEntry`) — mirrors `InventoryItem`'s
/// tenant-independent-snapshot scoping, not a shared global record.
class NutritionReferenceEntry {
  const NutritionReferenceEntry({
    required this.id,
    required this.organizationId,
    required this.ingredientId,
    required this.values,
    required this.referenceUnit,
    required this.sourceType,
    this.sourceName,
    this.sourceRecordId,
    this.sourceRevision,
    this.sourceDate,
    required this.confidence,
    required this.isManuallyOverridden,
    this.reviewedByStaffId,
    this.reviewedAt,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String ingredientId;
  final NutritionValueSet values;

  /// [InventoryUnit.gram] or [InventoryUnit.milliliter] — every value
  /// in [values] is "per 100" of this unit.
  final InventoryUnit referenceUnit;

  final NutritionDataSourceType sourceType;
  final String? sourceName;
  final String? sourceRecordId;
  final String? sourceRevision;
  final DateTime? sourceDate;
  final NutritionConfidence confidence;
  final bool isManuallyOverridden;
  final String? reviewedByStaffId;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final int revision;

  NutritionReferenceEntry copyWith({
    NutritionValueSet? values,
    NutritionDataSourceType? sourceType,
    String? sourceName,
    bool clearSourceName = false,
    String? sourceRecordId,
    bool clearSourceRecordId = false,
    String? sourceRevision,
    bool clearSourceRevision = false,
    DateTime? sourceDate,
    bool clearSourceDate = false,
    NutritionConfidence? confidence,
    bool? isManuallyOverridden,
    String? reviewedByStaffId,
    DateTime? reviewedAt,
    required int revision,
  }) {
    return NutritionReferenceEntry(
      id: id,
      organizationId: organizationId,
      ingredientId: ingredientId,
      values: values ?? this.values,
      referenceUnit: referenceUnit,
      sourceType: sourceType ?? this.sourceType,
      sourceName: clearSourceName ? null : (sourceName ?? this.sourceName),
      sourceRecordId:
          clearSourceRecordId ? null : (sourceRecordId ?? this.sourceRecordId),
      sourceRevision:
          clearSourceRevision ? null : (sourceRevision ?? this.sourceRevision),
      sourceDate: clearSourceDate ? null : (sourceDate ?? this.sourceDate),
      confidence: confidence ?? this.confidence,
      isManuallyOverridden: isManuallyOverridden ?? this.isManuallyOverridden,
      reviewedByStaffId: reviewedByStaffId ?? this.reviewedByStaffId,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
