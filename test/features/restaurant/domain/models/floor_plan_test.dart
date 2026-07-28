import 'package:abakus_one_v2/features/restaurant/domain/models/floor_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith only changes the given fields', () {
    const plan = FloorPlan(
      id: 'floor-1',
      branchId: 'branch-1',
      name: 'Zemin Kat',
      sortOrder: 0,
      isActive: true,
    );

    final updated = plan.copyWith(name: 'Teras', isActive: false);

    expect(updated.name, 'Teras');
    expect(updated.isActive, isFalse);
    expect(updated.id, plan.id);
    expect(updated.branchId, plan.branchId);
    expect(updated.sortOrder, plan.sortOrder);
  });
}
