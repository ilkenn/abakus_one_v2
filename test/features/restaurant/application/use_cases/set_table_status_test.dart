import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/qr/domain/models/restaurant_table.dart';
import 'package:abakus_one_v2/features/restaurant/application/use_cases/set_table_status.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_table_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('updates only the table status', () async {
    final repository = InMemoryRestaurantTableRepository();
    await repository.save(const RestaurantTable(
      id: 'table-1',
      branchId: 'branch-1',
      floorPlanId: 'floor-1',
      displayName: 'Masa 1',
      areaName: '',
      capacity: 4,
      status: TableStatus.available,
      sortOrder: 0,
      isActive: true,
    ));
    final useCase = SetTableStatus(repository: repository);

    final updated =
        await useCase(tableId: 'table-1', status: TableStatus.occupied);

    expect(updated.status, TableStatus.occupied);
    expect(updated.displayName, 'Masa 1');
  });

  test('throws UnknownRestaurantOperationsEntityViolation for an unknown table',
      () async {
    final repository = InMemoryRestaurantTableRepository();
    final useCase = SetTableStatus(repository: repository);

    expect(
      () => useCase(tableId: 'missing', status: TableStatus.occupied),
      throwsA(isA<UnknownRestaurantOperationsEntityViolation>()),
    );
  });
}
