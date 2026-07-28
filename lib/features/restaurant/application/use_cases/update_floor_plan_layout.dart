import '../../../../core/errors/business_rule_violation.dart';
import '../../../qr/domain/models/restaurant_table.dart';
import '../../data/restaurant_table_repository.dart';

/// One table's new position/rotation, as produced by the floor-plan
/// editor's drag-and-drop interaction.
class TableLayoutUpdate {
  const TableLayoutUpdate({
    required this.tableId,
    required this.positionX,
    required this.positionY,
    this.rotationDegrees,
  });

  final String tableId;
  final double positionX;
  final double positionY;
  final double? rotationDegrees;
}

/// Applies a batch of position/rotation updates from the floor-plan editor
/// in one call, so a drag-and-drop session that moved several tables
/// persists as one coherent operation rather than N separate saves.
///
/// Throws [UnknownRestaurantOperationsEntityViolation] for any
/// [TableLayoutUpdate.tableId] that doesn't resolve — the whole batch is
/// validated before any table is saved, so a bad id never leaves the
/// layout partially applied.
class UpdateFloorPlanLayout {
  const UpdateFloorPlanLayout({required RestaurantTableRepository repository})
      : _repository = repository;

  final RestaurantTableRepository _repository;

  Future<void> call(List<TableLayoutUpdate> updates) async {
    final resolved = <String, RestaurantTable>{};
    for (final update in updates) {
      final table = await _repository.findById(update.tableId);
      if (table == null) {
        throw UnknownRestaurantOperationsEntityViolation(
          entityName: 'RestaurantTable',
          id: update.tableId,
        );
      }
      resolved[update.tableId] = table;
    }

    for (final update in updates) {
      final table = resolved[update.tableId]!;
      await _repository.save(
        table.copyWith(
          positionX: update.positionX,
          positionY: update.positionY,
          rotationDegrees: update.rotationDegrees ?? table.rotationDegrees,
        ),
      );
    }
  }
}
