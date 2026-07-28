import 'package:abakus_one_v2/features/restaurant/data/floor_plan_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/floor_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryFloorPlanRepository', () {
    test('save then findById returns the saved plan', () async {
      final repository = InMemoryFloorPlanRepository();
      const plan = FloorPlan(
        id: 'floor-1',
        branchId: 'branch-1',
        name: 'Zemin Kat',
        sortOrder: 0,
        isActive: true,
      );

      await repository.save(plan);

      expect(await repository.findById('floor-1'), plan);
    });

    test('findById returns null for an unknown id', () async {
      final repository = InMemoryFloorPlanRepository();

      expect(await repository.findById('missing'), isNull);
    });

    test('findByBranchId only returns plans for that branch', () async {
      final repository = InMemoryFloorPlanRepository();
      await repository.save(const FloorPlan(
        id: 'floor-1',
        branchId: 'branch-a',
        name: 'Zemin Kat',
        sortOrder: 0,
        isActive: true,
      ));
      await repository.save(const FloorPlan(
        id: 'floor-2',
        branchId: 'branch-b',
        name: 'Teras',
        sortOrder: 0,
        isActive: true,
      ));

      final results = await repository.findByBranchId('branch-a');

      expect(results.map((p) => p.id), ['floor-1']);
    });
  });
}
