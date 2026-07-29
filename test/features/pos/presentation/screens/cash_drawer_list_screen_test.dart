import 'package:abakus_one_v2/features/pos/data/cash_drawer_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_drawer.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/cash_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/cash_drawer_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<InMemoryCashDrawerRepository> pumpScreen(
    WidgetTester tester, {
    List<CashDrawer> seedDrawers = const [],
  }) async {
    final repository = InMemoryCashDrawerRepository();
    for (final drawer in seedDrawers) {
      await repository.save(drawer);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [cashDrawerRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: CashDrawerListScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('an empty repository shows the empty-state view', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Bu şubede henüz kasa yok'), findsOneWidget);
  });

  testWidgets('lists drawers registered for the branch', (tester) async {
    await pumpScreen(tester, seedDrawers: [
      const CashDrawer(id: 'drawer-1', branchId: 'branch-1', name: 'Ön Kasa'),
      const CashDrawer(
        id: 'drawer-2',
        branchId: 'branch-1',
        name: 'Arka Kasa',
        isActive: false,
      ),
    ]);

    expect(find.text('Ön Kasa'), findsOneWidget);
    expect(find.text('Aktif'), findsOneWidget);
    expect(find.text('Arka Kasa'), findsOneWidget);
    expect(find.text('Arşivlendi'), findsOneWidget);
  });

  testWidgets('adding a drawer via the dialog appends it to the list',
      (tester) async {
    final repository = await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Yeni Kasa');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ekle'));
    await tester.pumpAndSettle();

    expect(find.text('Yeni Kasa'), findsOneWidget);
    final drawers = await repository.findByBranchId('branch-1');
    expect(drawers, hasLength(1));
    expect(drawers.single.name, 'Yeni Kasa');
  });
}
