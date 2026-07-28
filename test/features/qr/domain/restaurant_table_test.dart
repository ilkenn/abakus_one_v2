import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/domain/models/restaurant_table.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/table_shape.dart';

RestaurantTable buildTable({
  TableStatus status = TableStatus.available,
  bool isActive = true,
}) {
  return RestaurantTable(
    id: 'table_1',
    branchId: 'branch_1',
    floorPlanId: 'floor_1',
    displayName: 'Masa 1',
    areaName: 'Teras',
    capacity: 4,
    status: status,
    sortOrder: 1,
    isActive: isActive,
  );
}

void main() {
  test('TableStatus tum operasyonel durumlari icerir', () {
    expect(TableStatus.values, [
      TableStatus.available,
      TableStatus.occupied,
      TableStatus.reserved,
      TableStatus.cleaning,
      TableStatus.disabled,
    ]);
  });

  group('RestaurantTable.isOrderable', () {
    test('aktif ve available ise true doner', () {
      final table = buildTable(status: TableStatus.available, isActive: true);
      expect(table.isOrderable, isTrue);
    });

    test('occupied ise false doner', () {
      final table = buildTable(status: TableStatus.occupied, isActive: true);
      expect(table.isOrderable, isFalse);
    });

    test('isActive false ise available olsa bile false doner', () {
      final table = buildTable(status: TableStatus.available, isActive: false);
      expect(table.isOrderable, isFalse);
    });
  });

  test('copyWith yalnizca verilen alanlari degistirir', () {
    final table = buildTable();
    final updated = table.copyWith(status: TableStatus.cleaning);

    expect(updated.status, TableStatus.cleaning);
    expect(updated.id, table.id);
    expect(updated.displayName, table.displayName);
  });

  group('floor plan layout fields (Phase 3 Sprint 3D)', () {
    test('default to an unplaced square when not supplied', () {
      final table = buildTable();

      expect(table.positionX, 0);
      expect(table.positionY, 0);
      expect(table.shape, TableShape.square);
      expect(table.rotationDegrees, 0);
      expect(table.width, 80);
      expect(table.height, 80);
    });

    test('copyWith updates position/shape/rotation independently', () {
      final table = buildTable();

      final placed = table.copyWith(
        positionX: 120,
        positionY: 40,
        shape: TableShape.round,
        rotationDegrees: 45,
      );

      expect(placed.positionX, 120);
      expect(placed.positionY, 40);
      expect(placed.shape, TableShape.round);
      expect(placed.rotationDegrees, 45);
      expect(placed.width, table.width);
    });
  });
}
