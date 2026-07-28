import 'package:abakus_one_v2/features/pos/application/identity/pos_order_line_draft_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SequentialPosOrderLineDraftIdGenerator', () {
    test('never repeats within one instance', () {
      final generator = SequentialPosOrderLineDraftIdGenerator();

      final ids = List.generate(5, (_) => generator.nextDraftId());

      expect(ids.toSet(), hasLength(5));
    });

    test(
        'two separate instances can produce the same sequence value (only unique within one runtime)',
        () {
      final a = SequentialPosOrderLineDraftIdGenerator();
      final b = SequentialPosOrderLineDraftIdGenerator();

      expect(a.nextDraftId(), b.nextDraftId());
    });

    test('prefix distinguishes generators when needed', () {
      final a = SequentialPosOrderLineDraftIdGenerator(prefix: 'session-a');
      final b = SequentialPosOrderLineDraftIdGenerator(prefix: 'session-b');

      expect(a.nextDraftId(), isNot(b.nextDraftId()));
    });
  });
}
