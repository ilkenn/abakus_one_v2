import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/domain/models/restaurant_table.dart';

RestaurantTable buildTable({
  TableStatus status = TableStatus.available,
  bool isActive = true,
}) {
  return RestaurantTable(
    id: 'table_1',
    branchId: 'branch_1',
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
}
