import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../domain/branch_stock.dart';
import '../../domain/quantity.dart';
import '../../domain/stock_movement_type.dart';
import 'record_stock_movement.dart';

/// The screen-facing entry point for a staff member manually recording
/// a stock movement (a transfer, a correction outside the formal
/// `StockAdjustment` approval flow, a goods-receipt line) — manager+
/// (`PosAuthorizedAction.recordStockMovement`). Checks authorization,
/// then delegates to the trusted internal `RecordStockMovement`
/// primitive — see that class's own doc comment for why the two are
/// split.
class RecordManualStockMovement {
  const RecordManualStockMovement({
    required PosAuthorizationPolicy authorizationPolicy,
    required RecordStockMovement recordStockMovement,
  })  : _authorizationPolicy = authorizationPolicy,
        _recordStockMovement = recordStockMovement;

  final PosAuthorizationPolicy _authorizationPolicy;
  final RecordStockMovement _recordStockMovement;

  Future<BranchStock> call({
    required String branchId,
    required String inventoryItemId,
    required String locationId,
    required StockMovementType type,
    required Quantity quantityDelta,
    String? lotId,
    String? reason,
    required String idempotencyKey,
    required String performedByStaffId,
    required DateTime occurredAt,
  }) async {
    const action = PosAuthorizedAction.recordStockMovement;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    return _recordStockMovement(
      branchId: branchId,
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      type: type,
      quantityDelta: quantityDelta,
      lotId: lotId,
      reason: reason,
      idempotencyKey: idempotencyKey,
      performedByStaffId: performedByStaffId,
      occurredAt: occurredAt,
    );
  }
}
