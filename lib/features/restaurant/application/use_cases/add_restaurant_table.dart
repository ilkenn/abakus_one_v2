import '../../../../core/errors/business_rule_violation.dart';
import '../../../qr/domain/models/restaurant_table.dart';
import '../../data/floor_plan_repository.dart';
import '../../data/restaurant_table_repository.dart';
import '../../domain/models/table_shape.dart';
import '../identity/restaurant_table_id_generator.dart';

/// Adds a new [RestaurantTable] to an existing [FloorPlan].
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if [floorPlanId]
/// does not resolve — a table is never created against a floor plan that
/// doesn't exist.
class AddRestaurantTable {
  const AddRestaurantTable({
    required RestaurantTableIdGenerator idGenerator,
    required RestaurantTableRepository tableRepository,
    required FloorPlanRepository floorPlanRepository,
  })  : _idGenerator = idGenerator,
        _tableRepository = tableRepository,
        _floorPlanRepository = floorPlanRepository;

  final RestaurantTableIdGenerator _idGenerator;
  final RestaurantTableRepository _tableRepository;
  final FloorPlanRepository _floorPlanRepository;

  Future<RestaurantTable> call({
    required String floorPlanId,
    required String branchId,
    required String displayName,
    String areaName = '',
    required int capacity,
    int sortOrder = 0,
    double positionX = 0,
    double positionY = 0,
    TableShape shape = TableShape.square,
    double width = 80,
    double height = 80,
  }) async {
    final floorPlan = await _floorPlanRepository.findById(floorPlanId);
    if (floorPlan == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'FloorPlan',
        id: floorPlanId,
      );
    }

    final table = RestaurantTable(
      id: _idGenerator.nextTableId(),
      branchId: branchId,
      floorPlanId: floorPlanId,
      displayName: displayName,
      areaName: areaName,
      capacity: capacity,
      status: TableStatus.available,
      sortOrder: sortOrder,
      isActive: true,
      positionX: positionX,
      positionY: positionY,
      shape: shape,
      width: width,
      height: height,
    );
    await _tableRepository.save(table);
    return table;
  }
}
