import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abakus_one_v2/features/cart/data/dine_in_offline_order_queue_repository.dart';
import 'package:abakus_one_v2/features/cart/domain/models/pending_dine_in_submission.dart';

PendingDineInSubmission _submission({
  String submissionKey = 'key-1',
  String tableSessionId = 'table-session-1',
}) {
  return PendingDineInSubmission(
    submissionKey: submissionKey,
    tableSessionId: tableSessionId,
    items: const [
      {'kind': 'bowl', 'quantity': 1, 'ingredientIds': <String>[], 'note': ''},
    ],
    customerNote: '',
    queuedAt: DateTime.utc(2026, 11, 6, 9, 0),
  );
}

void main() {
  group('SharedPreferencesDineInOfflineOrderQueueRepository', () {
    test('enqueue then findAll round-trips the entry', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesDineInOfflineOrderQueueRepository(
          await SharedPreferences.getInstance());

      await repo.enqueue(_submission());
      final all = await repo.findAll();

      expect(all, hasLength(1));
      expect(all.single.submissionKey, 'key-1');
      expect(all.single.tableSessionId, 'table-session-1');
    });

    test(
        'a durable queue survives a fresh SharedPreferences.getInstance() call — proves persistence, not just in-memory state',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefsBefore = await SharedPreferences.getInstance();
      await SharedPreferencesDineInOfflineOrderQueueRepository(prefsBefore)
          .enqueue(_submission());

      final prefsAfter = await SharedPreferences.getInstance();
      final reopened =
          SharedPreferencesDineInOfflineOrderQueueRepository(prefsAfter);
      final all = await reopened.findAll();

      expect(all, hasLength(1));
      expect(all.single.submissionKey, 'key-1');
    });

    test(
        'enqueue is idempotent by submissionKey — a double-tap enqueue never duplicates',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesDineInOfflineOrderQueueRepository(
          await SharedPreferences.getInstance());

      await repo.enqueue(_submission());
      await repo.enqueue(_submission());

      expect(await repo.findAll(), hasLength(1));
    });

    test('remove deletes only the matching entry, by submissionKey', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesDineInOfflineOrderQueueRepository(
          await SharedPreferences.getInstance());
      await repo.enqueue(_submission(submissionKey: 'key-a'));
      await repo.enqueue(_submission(submissionKey: 'key-b'));

      await repo.remove('key-a');

      final remaining = await repo.findAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.submissionKey, 'key-b');
    });

    test('removing a submissionKey that was never enqueued is a no-op',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesDineInOfflineOrderQueueRepository(
          await SharedPreferences.getInstance());
      await repo.enqueue(_submission());

      await repo.remove('does-not-exist');

      expect(await repo.findAll(), hasLength(1));
    });

    test('findAll on an empty queue returns an empty list, never null/throws',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesDineInOfflineOrderQueueRepository(
          await SharedPreferences.getInstance());

      expect(await repo.findAll(), isEmpty);
    });
  });
}
