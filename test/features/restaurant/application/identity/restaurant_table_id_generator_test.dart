import 'package:abakus_one_v2/features/restaurant/application/identity/restaurant_table_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SequentialRestaurantTableIdGenerator', () {
    test('never repeats within one instance', () {
      final generator = SequentialRestaurantTableIdGenerator();

      final ids = List.generate(5, (_) => generator.nextTableId());

      expect(ids.toSet(), hasLength(5));
    });
  });
}
