import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/waste_record_repository.dart';
import '../../domain/quantity.dart';
import '../../domain/stock_movement_type.dart';
import '../../domain/waste_record.dart';
import '../identity/waste_record_id_generator.dart';
import 'record_stock_movement.dart';

/// Records a [WasteRecord] and its corresponding real
/// [StockMovementType.waste] `StockMovement` — staff+
/// (`PosAuthorizedAction.recordWaste`), Phase 7
/// (`docs/decisions.md` ADR-024). "Waste requires reason" — [reason]
/// must be non-empty. Waste and stock-count variance stay in
/// deliberately separate repositories/records — "waste and count
/// variance must remain separately reportable."
class RecordWaste {
  const RecordWaste({
    required PosAuthorizationPolicy authorizationPolicy,
    required WasteRecordIdGenerator idGenerator,
    required WasteRecordRepository repository,
    required RecordStockMovement recordStockMovement,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _recordStockMovement = recordStockMovement;

  final PosAuthorizationPolicy _authorizationPolicy;
  final WasteRecordIdGenerator _idGenerator;
  final WasteRecordRepository _repository;
  final RecordStockMovement _recordStockMovement;

  Future<WasteRecord> call({
    required String branchId,
    required String inventoryItemId,
    required String locationId,
    required Quantity quantity,
    required String reason,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.recordWaste;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (reason.trim().isEmpty) {
      throw const InventoryReasonRequiredViolation();
    }

    final id = _idGenerator.nextWasteRecordId();
    // WasteRecord.quantity is always the positive wasted amount; the
    // underlying StockMovement is always the negative delta that
    // actually reduces on-hand quantity.
    final positiveQuantity = quantity.isNegative ? -quantity : quantity;
    final idempotencyKey = 'waste-$id';

    await _recordStockMovement(
      branchId: branchId,
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      type: StockMovementType.waste,
      quantityDelta: -positiveQuantity,
      reason: reason,
      idempotencyKey: idempotencyKey,
      performedByStaffId: performedByStaffId,
      occurredAt: performedAt,
    );

    final record = WasteRecord(
      id: id,
      branchId: branchId,
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      quantity: positiveQuantity,
      reason: reason,
      relatedStockMovementId: idempotencyKey,
      reportedByStaffId: performedByStaffId,
      occurredAt: performedAt,
    );
    await _repository.append(record);
    return record;
  }
}
