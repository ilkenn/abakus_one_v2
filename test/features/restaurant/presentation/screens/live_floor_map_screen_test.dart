import 'package:abakus_one_v2/features/qr/domain/models/restaurant_table.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_table_repository.dart';
import 'package:abakus_one_v2/features/restaurant/presentation/providers/restaurant_operations_dependencies_provider.dart';
import 'package:abakus_one_v2/features/restaurant/presentation/screens/live_floor_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<InMemoryRestaurantTableRepository> pumpScreen(
      WidgetTester tester) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          restaurantTableRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: LiveFloorMapScreen(
              floorPlanId: 'floor-1', floorPlanName: 'Zemin Kat'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('shows every table on the floor plan', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Masa 1'), findsOneWidget);
  });

  testWidgets('tapping a table cycles its status', (tester) async {
    final repository = await pumpScreen(tester);

    await tester.tap(find.text('Masa 1'));
    await tester.pumpAndSettle();

    final table = await repository.findById('table-1');
    expect(table!.status, TableStatus.occupied);
  });

  testWidgets('an empty floor plan shows the empty state', (tester) async {
    final repository = InMemoryRestaurantTableRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          restaurantTableRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: LiveFloorMapScreen(
              floorPlanId: 'floor-1', floorPlanName: 'Zemin Kat'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bu kat planında henüz masa yok'), findsOneWidget);
  });
}
