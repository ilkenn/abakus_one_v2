import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/expiry_record_repository.dart';
import '../../data/stock_lot_repository.dart';
import '../../domain/expiry_record.dart';
import '../../domain/stock_movement_type.dart';
import '../identity/expiry_record_id_generator.dart';
import 'record_stock_movement.dart';

/// Disposes some or all of an expired [StockLot] — staff+
/// (`PosAuthorizedAction.recordWaste`, reused rather than adding an
/// expiry-specific action for the same "food is being thrown away"
/// act), Phase 7 (`docs/decisions.md` ADR-024). "Expired inventory
/// cannot be treated as saleable stock" — enforced by actually
/// reducing on-hand quantity through the same
/// [StockMovementType.waste] `StockMovement` a normal waste report
/// produces, never a passive flag no other code reads.
class DisposeExpiredLot {
  const DisposeExpiredLot({
    required PosAuthorizationPolicy authorizationPolicy,
    required ExpiryRecordIdGenerator idGenerator,
    required StockLotRepository lotRepository,
    required ExpiryRecordRepository repository,
    required RecordStockMovement recordStockMovement,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _lotRepository = lotRepository,
        _repository = repository,
        _recordStockMovement = recordStockMovement;

  final PosAuthorizationPolicy _authorizationPolicy;
  final ExpiryRecordIdGenerator _idGenerator;
  final StockLotRepository _lotRepository;
  final ExpiryRecordRepository _repository;
  final RecordStockMovement _recordStockMovement;

  Future<ExpiryRecord> call({
    required String branchId,
    required String lotId,
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

    final lot = await _lotRepository.findById(lotId);
    if (lot == null) {
      throw UnknownInventoryEntityViolation(
        entityName: 'StockLot',
        id: lotId,
      );
    }

    final id = _idGenerator.nextExpiryRecordId();
    final idempotencyKey = 'expiry-$id';
    final disposedQuantity = lot.quantityRemaining;

    if (!disposedQuantity.isZero) {
      await _recordStockMovement(
        branchId: branchId,
        inventoryItemId: lot.inventoryItemId,
        locationId: lot.locationId,
        type: StockMovementType.waste,
        quantityDelta: -disposedQuantity,
        lotId: lot.id,
        reason: 'Son kullanma tarihi geçti',
        idempotencyKey: idempotencyKey,
        performedByStaffId: performedByStaffId,
        occurredAt: performedAt,
      );
    }

    final record = ExpiryRecord(
      id: id,
      lotId: lot.id,
      inventoryItemId: lot.inventoryItemId,
      locationId: lot.locationId,
      disposedQuantity: disposedQuantity,
      relatedStockMovementId: disposedQuantity.isZero ? null : idempotencyKey,
      disposedByStaffId: performedByStaffId,
      disposedAt: performedAt,
    );
    await _repository.append(record);
    return record;
  }
}
