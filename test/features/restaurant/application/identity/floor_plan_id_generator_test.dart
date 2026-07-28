import 'package:abakus_one_v2/features/restaurant/application/identity/floor_plan_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SequentialFloorPlanIdGenerator', () {
    test('never repeats within one instance', () {
      final generator = SequentialFloorPlanIdGenerator();

      final ids = List.generate(5, (_) => generator.nextFloorPlanId());

      expect(ids.toSet(), hasLength(5));
    });

    test('prefix distinguishes generators when needed', () {
      final a = SequentialFloorPlanIdGenerator(prefix: 'branch-a');
      final b = SequentialFloorPlanIdGenerator(prefix: 'branch-b');

      expect(a.nextFloorPlanId(), isNot(b.nextFloorPlanId()));
    });
  });
}
