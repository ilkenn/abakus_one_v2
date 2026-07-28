import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/qr/domain/models/restaurant_table.dart';
import 'package:abakus_one_v2/features/restaurant/application/use_cases/update_floor_plan_layout.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_table_repository.dart';
import 'package:flutter_test/flutter_test.dart';

RestaurantTable _buildTable(String id) {
  return RestaurantTable(
    id: id,
    branchId: 'branch-1',
    floorPlanId: 'floor-1',
    displayName: id,
    areaName: '',
    capacity: 4,
    status: TableStatus.available,
    sortOrder: 0,
    isActive: true,
  );
}

void main() {
  test('applies a batch of position updates to every referenced table',
      () async {
    final repository = InMemoryRestaurantTableRepository();
    await repository.save(_buildTable('table-1'));
    await repository.save(_buildTable('table-2'));
    final useCase = UpdateFloorPlanLayout(repository: repository);

    await useCase([
      const TableLayoutUpdate(
          tableId: 'table-1', positionX: 100, positionY: 50),
      const TableLayoutUpdate(
          tableId: 'table-2',
          positionX: 200,
          positionY: 60,
          rotationDegrees: 90),
    ]);

    final table1 = await repository.findById('table-1');
    final table2 = await repository.findById('table-2');
    expect(table1!.positionX, 100);
    expect(table1.positionY, 50);
    expect(table2!.rotationDegrees, 90);
  });

  test(
      'throws for an unknown table id and leaves every table unchanged (validated before saving)',
      () async {
    final repository = InMemoryRestaurantTableRepository();
    final original = _buildTable('table-1');
    await repository.save(original);
    final useCase = UpdateFloorPlanLayout(repository: repository);

    await expectLater(
      () => useCase([
        const TableLayoutUpdate(
            tableId: 'table-1', positionX: 999, positionY: 999),
        const TableLayoutUpdate(tableId: 'missing', positionX: 1, positionY: 1),
      ]),
      throwsA(isA<UnknownRestaurantOperationsEntityViolation>()),
    );

    final table1 = await repository.findById('table-1');
    expect(table1!.positionX, original.positionX);
  });
}
