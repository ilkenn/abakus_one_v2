import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/branch_stock_repository.dart';
import '../../data/stock_count_line_repository.dart';
import '../../data/stock_count_repository.dart';
import '../../domain/quantity.dart';
import '../../domain/stock_count.dart';
import '../../domain/stock_count_line.dart';
import '../identity/stock_count_line_id_generator.dart';

/// Adds one counted [InventoryItem] line to an in-progress
/// [StockCount] — staff+ (`PosAuthorizedAction.recordStockCount`),
/// Phase 7 (`docs/decisions.md` ADR-024). [expectedQuantity] is
/// resolved from the current `BranchStock` at the moment the line is
/// added (zero if no balance is on record yet) — the
/// [StockCountLine.varianceQuantity] is then computed structurally by
/// the domain type itself.
class AddStockCountLine {
  const AddStockCountLine({
    required PosAuthorizationPolicy authorizationPolicy,
    required StockCountLineIdGenerator idGenerator,
    required StockCountRepository countRepository,
    required StockCountLineRepository lineRepository,
    required BranchStockRepository branchStockRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _countRepository = countRepository,
        _lineRepository = lineRepository,
        _branchStockRepository = branchStockRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StockCountLineIdGenerator _idGenerator;
  final StockCountRepository _countRepository;
  final StockCountLineRepository _lineRepository;
  final BranchStockRepository _branchStockRepository;

  Future<StockCountLine> call({
    required String countId,
    required String inventoryItemId,
    required String locationId,
    required Quantity countedQuantity,
    required String performedByStaffId,
  }) async {
    final count = await _countRepository.findById(countId);
    if (count == null) {
      throw UnknownInventoryEntityViolation(
        entityName: 'StockCount',
        id: countId,
      );
    }

    const action = PosAuthorizedAction.recordStockCount;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: count.branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (count.status != StockCountStatus.inProgress) {
      throw InvalidInventoryWorkflowTransitionViolation(
        fromStatusName: count.status.name,
        toStatusName: 'lineAdded',
      );
    }

    final balance = await _branchStockRepository.findByItemAndLocation(
        inventoryItemId, locationId);
    final expectedQuantity =
        balance?.quantityOnHand ?? Quantity.zero(countedQuantity.unit);

    final line = StockCountLine(
      id: _idGenerator.nextStockCountLineId(),
      countId: countId,
      inventoryItemId: inventoryItemId,
      expectedQuantity: expectedQuantity,
      countedQuantity: countedQuantity,
    );
    await _lineRepository.save(line);
    return line;
  }
}
