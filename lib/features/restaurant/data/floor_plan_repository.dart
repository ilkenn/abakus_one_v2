import '../domain/models/floor_plan.dart';

/// Storage for [FloorPlan] records — a mutable, editable operational
/// record (not append-only; unlike a financial/audit record, a floor
/// plan's own current shape is what matters, not its edit history).
abstract interface class FloorPlanRepository {
  Future<void> save(FloorPlan floorPlan);

  Future<FloorPlan?> findById(String floorPlanId);

  Future<List<FloorPlan>> findByBranchId(String branchId);
}

/// In-memory [FloorPlanRepository] — the only implementation this sprint.
class InMemoryFloorPlanRepository implements FloorPlanRepository {
  final Map<String, FloorPlan> _floorPlansById = {};

  @override
  Future<void> save(FloorPlan floorPlan) async {
    _floorPlansById[floorPlan.id] = floorPlan;
  }

  @override
  Future<FloorPlan?> findById(String floorPlanId) async {
    return _floorPlansById[floorPlanId];
  }

  @override
  Future<List<FloorPlan>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _floorPlansById.values.where((plan) => plan.branchId == branchId),
    );
  }
}
