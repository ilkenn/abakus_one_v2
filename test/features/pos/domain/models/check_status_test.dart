import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CheckStatusTransitions', () {
    test('open can move to submitted or cancelled', () {
      expect(
        CheckStatusTransitions.canTransition(
            CheckStatus.open, CheckStatus.submitted),
        isTrue,
      );
      expect(
        CheckStatusTransitions.canTransition(
            CheckStatus.open, CheckStatus.cancelled),
        isTrue,
      );
    });

    test('submitted and cancelled are terminal', () {
      expect(
        CheckStatusTransitions.canTransition(
            CheckStatus.submitted, CheckStatus.open),
        isFalse,
      );
      expect(
        CheckStatusTransitions.canTransition(
            CheckStatus.cancelled, CheckStatus.open),
        isFalse,
      );
    });
  });
}
