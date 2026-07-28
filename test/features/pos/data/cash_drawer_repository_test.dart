import 'package:abakus_one_v2/features/pos/data/cash_drawer_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_drawer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('save then findById returns the saved drawer', () async {
    final repository = InMemoryCashDrawerRepository();
    const drawer =
        CashDrawer(id: 'drawer-1', branchId: 'branch-1', name: 'Kasa 1');

    await repository.save(drawer);

    expect(await repository.findById('drawer-1'), drawer);
  });

  test('findByBranchId only returns drawers for that branch', () async {
    final repository = InMemoryCashDrawerRepository();
    await repository.save(
        const CashDrawer(id: 'drawer-1', branchId: 'branch-a', name: 'Kasa 1'));
    await repository.save(
        const CashDrawer(id: 'drawer-2', branchId: 'branch-b', name: 'Kasa 2'));

    final results = await repository.findByBranchId('branch-a');

    expect(results.map((d) => d.id), ['drawer-1']);
  });
}
