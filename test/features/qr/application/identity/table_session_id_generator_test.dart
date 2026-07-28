import 'package:abakus_one_v2/features/qr/application/identity/table_session_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never repeats within one instance', () {
    final generator = SequentialTableSessionIdGenerator();

    final ids = List.generate(5, (_) => generator.nextTableSessionId());

    expect(ids.toSet(), hasLength(5));
  });
}
