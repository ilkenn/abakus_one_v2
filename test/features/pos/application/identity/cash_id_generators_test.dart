import 'package:abakus_one_v2/features/pos/application/identity/cash_drawer_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_session_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SequentialCashDrawerIdGenerator never repeats within one instance', () {
    final generator = SequentialCashDrawerIdGenerator();
    final ids = List.generate(5, (_) => generator.nextDrawerId());
    expect(ids.toSet(), hasLength(5));
  });

  test('SequentialCashSessionIdGenerator never repeats within one instance',
      () {
    final generator = SequentialCashSessionIdGenerator();
    final ids = List.generate(5, (_) => generator.nextSessionId());
    expect(ids.toSet(), hasLength(5));
  });

  test('SequentialCashMovementIdGenerator never repeats within one instance',
      () {
    final generator = SequentialCashMovementIdGenerator();
    final ids = List.generate(5, (_) => generator.nextMovementId());
    expect(ids.toSet(), hasLength(5));
  });
}
