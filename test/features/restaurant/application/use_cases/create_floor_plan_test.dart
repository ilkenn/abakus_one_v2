import 'package:abakus_one_v2/features/restaurant/application/identity/floor_plan_id_generator.dart';
import 'package:abakus_one_v2/features/restaurant/application/use_cases/create_floor_plan.dart';
import 'package:abakus_one_v2/features/restaurant/data/floor_plan_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates and persists a new active floor plan', () async {
    final repository = InMemoryFloorPlanRepository();
    final useCase = CreateFloorPlan(
      idGenerator: SequentialFloorPlanIdGenerator(),
      repository: repository,
    );

    final plan = await useCase(branchId: 'branch-1', name: 'Zemin Kat');

    expect(plan.branchId, 'branch-1');
    expect(plan.name, 'Zemin Kat');
    expect(plan.isActive, isTrue);
    expect(await repository.findById(plan.id), plan);
  });
}
