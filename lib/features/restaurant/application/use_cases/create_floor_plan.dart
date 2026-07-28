import '../../data/floor_plan_repository.dart';
import '../../domain/models/floor_plan.dart';
import '../identity/floor_plan_id_generator.dart';

/// Creates and persists a new, empty [FloorPlan] for a branch.
class CreateFloorPlan {
  const CreateFloorPlan({
    required FloorPlanIdGenerator idGenerator,
    required FloorPlanRepository repository,
  })  : _idGenerator = idGenerator,
        _repository = repository;

  final FloorPlanIdGenerator _idGenerator;
  final FloorPlanRepository _repository;

  Future<FloorPlan> call({
    required String branchId,
    required String name,
    int sortOrder = 0,
  }) async {
    final floorPlan = FloorPlan(
      id: _idGenerator.nextFloorPlanId(),
      branchId: branchId,
      name: name,
      sortOrder: sortOrder,
      isActive: true,
    );
    await _repository.save(floorPlan);
    return floorPlan;
  }
}
