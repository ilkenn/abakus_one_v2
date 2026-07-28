import 'package:abakus_one_v2/features/pos/application/identity/check_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never repeats within one instance', () {
    final generator = SequentialCheckIdGenerator();

    final ids = List.generate(5, (_) => generator.nextCheckId());

    expect(ids.toSet(), hasLength(5));
  });
}
