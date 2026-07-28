import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/restaurant/application/identity/restaurant_table_id_generator.dart';
import 'package:abakus_one_v2/features/restaurant/application/use_cases/add_restaurant_table.dart';
import 'package:abakus_one_v2/features/restaurant/data/floor_plan_repository.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_table_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/floor_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryFloorPlanRepository floorPlanRepository;
  late InMemoryRestaurantTableRepository tableRepository;
  late AddRestaurantTable useCase;

  setUp(() async {
    floorPlanRepository = InMemoryFloorPlanRepository();
    tableRepository = InMemoryRestaurantTableRepository();
    useCase = AddRestaurantTable(
      idGenerator: SequentialRestaurantTableIdGenerator(),
      tableRepository: tableRepository,
      floorPlanRepository: floorPlanRepository,
    );
    await floorPlanRepository.save(const FloorPlan(
      id: 'floor-1',
      branchId: 'branch-1',
      name: 'Zemin Kat',
      sortOrder: 0,
      isActive: true,
    ));
  });

  test('adds a table to an existing floor plan, available by default',
      () async {
    final table = await useCase(
      floorPlanId: 'floor-1',
      branchId: 'branch-1',
      displayName: 'Masa 1',
      capacity: 4,
    );

    expect(table.floorPlanId, 'floor-1');
    expect(table.status.name, 'available');
    expect(table.isActive, isTrue);
    expect(await tableRepository.findById(table.id), table);
  });

  test(
      'throws UnknownRestaurantOperationsEntityViolation for an unknown floor plan',
      () async {
    expect(
      () => useCase(
        floorPlanId: 'missing',
        branchId: 'branch-1',
        displayName: 'Masa 1',
        capacity: 4,
      ),
      throwsA(isA<UnknownRestaurantOperationsEntityViolation>()),
    );
  });
}
