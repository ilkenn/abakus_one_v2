import '../../../inventory/application/use_cases/record_stock_movement.dart';
import '../../../inventory/data/inventory_item_repository.dart';
import '../../../inventory/domain/quantity.dart';
import '../../../inventory/domain/stock_movement_type.dart';
import '../../../recipes/data/recipe_version_repository.dart';
import '../../../recipes/data/sub_recipe_repository.dart';
import '../../../recipes/data/sub_recipe_version_repository.dart';
import '../../../recipes/domain/recipe_line_flattener.dart';
import '../../data/stock_consumption_audit_entry_repository.dart';
import '../../data/stock_consumption_record_repository.dart';
import '../../domain/order_line_recipe_reference.dart';
import '../../domain/stock_consumption_audit_entry.dart';
import '../../domain/stock_consumption_audit_event_type.dart';
import '../../domain/stock_consumption_record.dart';
import '../identity/stock_consumption_record_id_generator.dart';

/// Deducts stock for one order's lines from their **historical**
/// recipe versions — Phase 7 (`docs/decisions.md` ADR-024).
///
/// **A trusted internal primitive, not a screen-facing entry point**
/// — deliberately has no `PosAuthorizationPolicy` dependency, mirroring
/// `RecordStockMovement`'s own doc comment about the "Phase 7O order-
/// completion hook": this is meant to be invoked automatically from an
/// already-authorized upstream order-lifecycle action (e.g. a manager/
/// kitchen actor accepting or completing an order), not called
/// directly from a screen.
///
/// **Wiring gap, documented honestly**: this codebase has no linkage
/// yet between `features/orders`' `OrderLine`/`MenuProduct` and
/// `features/recipes`' `Recipe` — no menu product currently references
/// a recipe id at all. Connecting this use case to a real order-
/// lifecycle trigger (`CompleteKitchenOrderPreparation` or an order-
/// acceptance use case) requires that menu-to-recipe linkage, which is
/// a menu-domain change out of this part's scope — the same kind of
/// explicit, honest limitation Sprint 5E recorded for the dine-in
/// visit trigger. What's built here is the real, tested, idempotent
/// consumption engine itself, ready to be called the moment that
/// linkage exists.
///
/// **Idempotent per order line**: keyed by `orderId`+`orderLineId` —
/// a duplicate call for the same line is a safe no-op, never a double
/// deduction. Each ingredient's own `StockMovement` additionally
/// carries its own idempotency key, so a partial failure partway
/// through one line's ingredients can safely retry only what's left.
///
/// An ingredient with no `InventoryItem` tracking it yet is silently
/// skipped (not tracked in inventory = nothing to deduct) — mirrors
/// the "an ingredient can exist in a recipe before anyone decides to
/// track it in inventory" precedent (7F).
class ConsumeStockForOrder {
  ConsumeStockForOrder({
    required RecipeVersionRepository recipeVersionRepository,
    required SubRecipeRepository subRecipeRepository,
    required SubRecipeVersionRepository subRecipeVersionRepository,
    required InventoryItemRepository inventoryItemRepository,
    required RecordStockMovement recordStockMovement,
    required StockConsumptionRecordIdGenerator idGenerator,
    required StockConsumptionRecordRepository recordRepository,
    required StockConsumptionAuditEntryRepository auditRepository,
  })  : _recipeVersionRepository = recipeVersionRepository,
        _flattener = RecipeLineFlattener(
          subRecipeRepository: subRecipeRepository,
          subRecipeVersionRepository: subRecipeVersionRepository,
        ),
        _inventoryItemRepository = inventoryItemRepository,
        _recordStockMovement = recordStockMovement,
        _idGenerator = idGenerator,
        _recordRepository = recordRepository,
        _auditRepository = auditRepository;

  final RecipeVersionRepository _recipeVersionRepository;
  final RecipeLineFlattener _flattener;
  final InventoryItemRepository _inventoryItemRepository;
  final RecordStockMovement _recordStockMovement;
  final StockConsumptionRecordIdGenerator _idGenerator;
  final StockConsumptionRecordRepository _recordRepository;
  final StockConsumptionAuditEntryRepository _auditRepository;

  Future<List<StockConsumptionRecord>> call({
    required String orderId,
    required String branchId,
    required String locationId,
    required List<OrderLineRecipeReference> lines,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final results = <StockConsumptionRecord>[];

    for (final line in lines) {
      final idempotencyKey = 'stock-consumption-$orderId-${line.orderLineId}';
      final existing =
          await _recordRepository.findByIdempotencyKey(idempotencyKey);
      if (existing != null) {
        results.add(existing);
        continue;
      }

      final version =
          await _recipeVersionRepository.findById(line.recipeVersionId);
      if (version == null) continue;

      final flattened = await _flattener.flatten(version.lines);
      final ingredientKeys = <String>[];

      for (final ingredientLine in flattened) {
        final inventoryItem = await _inventoryItemRepository
            .findByIngredientId(ingredientLine.ingredientId);
        if (inventoryItem == null) continue;

        final ingredientIdempotencyKey =
            '$idempotencyKey-${ingredientLine.ingredientId}';
        final scaledQuantity = Quantity(
          -(ingredientLine.quantity.smallestUnits * line.orderedQuantity),
          ingredientLine.quantity.unit,
        );

        await _recordStockMovement(
          branchId: branchId,
          inventoryItemId: inventoryItem.id,
          locationId: locationId,
          type: StockMovementType.consumption,
          quantityDelta: scaledQuantity,
          relatedOrderId: orderId,
          idempotencyKey: ingredientIdempotencyKey,
          performedByStaffId: performedByStaffId,
          occurredAt: performedAt,
          correlationId: line.orderLineId,
        );
        ingredientKeys.add(ingredientIdempotencyKey);
      }

      final record = StockConsumptionRecord(
        id: _idGenerator.nextStockConsumptionRecordId(),
        idempotencyKey: idempotencyKey,
        orderId: orderId,
        orderLineId: line.orderLineId,
        branchId: branchId,
        locationId: locationId,
        recipeId: line.recipeId,
        recipeVersionId: line.recipeVersionId,
        ingredientIdempotencyKeys: ingredientKeys,
        consumedAt: performedAt,
      );
      await _recordRepository.save(record);
      results.add(record);

      await _auditRepository.appendEvent(StockConsumptionAuditEntry(
        id: '${record.id}-audit-consumed',
        branchId: branchId,
        actorId: performedByStaffId,
        type: StockConsumptionAuditEventType.orderLineConsumed,
        description: 'Stock consumed for order line "${line.orderLineId}" '
            '(${ingredientKeys.length} ingredient(s))',
        targetEntityId: record.id,
        timestamp: performedAt,
      ));
    }

    return results;
  }
}
