import 'package:abakus_one_v2/features/qr/domain/models/restaurant_table.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_table_repository.dart';
import 'package:flutter_test/flutter_test.dart';

RestaurantTable _buildTable({
  required String id,
  required String floorPlanId,
  String branchId = 'branch-1',
}) {
  return RestaurantTable(
    id: id,
    branchId: branchId,
    floorPlanId: floorPlanId,
    displayName: id,
    areaName: '',
    capacity: 4,
    status: TableStatus.available,
    sortOrder: 0,
    isActive: true,
  );
}

void main() {
  group('InMemoryRestaurantTableRepository', () {
    test('save then findById returns the saved table', () async {
      final repository = InMemoryRestaurantTableRepository();
      final table = _buildTable(id: 'table-1', floorPlanId: 'floor-1');

      await repository.save(table);

      expect(await repository.findById('table-1'), table);
    });

    test('findByFloorPlanId only returns tables on that floor plan', () async {
      final repository = InMemoryRestaurantTableRepository();
      await repository.save(_buildTable(id: 'table-1', floorPlanId: 'floor-a'));
      await repository.save(_buildTable(id: 'table-2', floorPlanId: 'floor-b'));

      final results = await repository.findByFloorPlanId('floor-a');

      expect(results.map((t) => t.id), ['table-1']);
    });

    test('findByBranchId only returns tables for that branch', () async {
      final repository = InMemoryRestaurantTableRepository();
      await repository.save(_buildTable(
        id: 'table-1',
        floorPlanId: 'floor-1',
        branchId: 'branch-a',
      ));
      await repository.save(_buildTable(
        id: 'table-2',
        floorPlanId: 'floor-1',
        branchId: 'branch-b',
      ));

      final results = await repository.findByBranchId('branch-a');

      expect(results.map((t) => t.id), ['table-1']);
    });
  });
}
