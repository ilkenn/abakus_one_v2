import 'package:abakus_one_v2/features/qr/domain/models/restaurant_table.dart';
import 'package:abakus_one_v2/features/restaurant/data/floor_plan_repository.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_table_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/floor_plan.dart';
import 'package:abakus_one_v2/features/restaurant/presentation/providers/restaurant_operations_dependencies_provider.dart';
import 'package:abakus_one_v2/features/restaurant/presentation/screens/floor_plan_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<
      ({
        InMemoryFloorPlanRepository floorPlanRepository,
        InMemoryRestaurantTableRepository tableRepository,
      })> pumpScreen(WidgetTester tester) async {
    final floorPlanRepository = InMemoryFloorPlanRepository();
    final tableRepository = InMemoryRestaurantTableRepository();
    await floorPlanRepository.save(const FloorPlan(
      id: 'floor-1',
      branchId: 'branch-1',
      name: 'Zemin Kat',
      sortOrder: 0,
      isActive: true,
    ));
    await tableRepository.save(const RestaurantTable(
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
          floorPlanRepositoryProvider.overrideWithValue(floorPlanRepository),
          restaurantTableRepositoryProvider.overrideWithValue(tableRepository),
        ],
        child: const MaterialApp(
          home: FloorPlanEditorScreen(
            floorPlanId: 'floor-1',
            floorPlanName: 'Zemin Kat',
            branchId: 'branch-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      floorPlanRepository: floorPlanRepository,
      tableRepository: tableRepository,
    );
  }

  testWidgets('shows existing tables and a disabled save button', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Masa 1'), findsOneWidget);
    final saveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Kaydet'),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets(
      'dragging a table enables save, and saving persists the new position',
      (tester) async {
    final repos = await pumpScreen(tester);

    await tester.drag(find.text('Masa 1'), const Offset(40, 30));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Kaydet'),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Kaydet'));
    await tester.pumpAndSettle();

    final table = await repos.tableRepository.findById('table-1');
    expect(table!.positionX, isNot(0));
  });

  testWidgets('adding a table via the dialog persists it', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Masa Adı'),
      'Masa 2',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ekle'));
    await tester.pumpAndSettle();

    expect(find.text('Masa 2'), findsOneWidget);
  });
}
