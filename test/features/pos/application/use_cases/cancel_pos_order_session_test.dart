import 'package:abakus_one_v2/features/pos/application/use_cases/cancel_pos_order_session.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/pos_test_fixtures.dart';

void main() {
  group('CancelPosOrderSession', () {
    test('deletes the draft stored under the given draftId', () async {
      final repository = InMemoryPosOrderRepository();
      final session = buildTestSession(sessionId: 'session-1');
      await repository.saveDraft('session-1', session);
      expect(repository.draftIds, contains('session-1'));

      await CancelPosOrderSession(repository: repository).call('session-1');

      expect(repository.draftIds, isNot(contains('session-1')));
    });

    test('deleting a non-existent draft does not throw', () async {
      final repository = InMemoryPosOrderRepository();

      await expectLater(
        CancelPosOrderSession(repository: repository).call('no-such-draft'),
        completes,
      );
    });
  });
}
