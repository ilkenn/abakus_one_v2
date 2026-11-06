import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/application/use_cases/sync_offline_dine_in_orders.dart';
import 'package:abakus_one_v2/features/cart/data/dine_in_offline_order_queue_repository.dart';
import 'package:abakus_one_v2/features/cart/data/submit_dine_in_order_gateway.dart';
import 'package:abakus_one_v2/features/cart/domain/models/pending_dine_in_submission.dart';

/// In-memory stand-in — mirrors
/// `SharedPreferencesDineInOfflineOrderQueueRepository`'s exact
/// enqueue/remove semantics without touching `shared_preferences`.
class _InMemoryDineInOfflineOrderQueueRepository
    implements DineInOfflineOrderQueueRepository {
  final List<PendingDineInSubmission> entries = [];

  @override
  Future<void> enqueue(PendingDineInSubmission submission) async {
    if (entries.any((e) => e.submissionKey == submission.submissionKey)) {
      return;
    }
    entries.add(submission);
  }

  @override
  Future<List<PendingDineInSubmission>> findAll() async =>
      List.unmodifiable(entries);

  @override
  Future<void> remove(String submissionKey) async {
    entries.removeWhere((e) => e.submissionKey == submissionKey);
  }
}

class _FakeSubmitDineInOrderGateway implements SubmitDineInOrderGateway {
  _FakeSubmitDineInOrderGateway({
    this.failingSubmissionKeys = const {},
  });

  final Set<String> failingSubmissionKeys;
  final List<String> submittedKeys = [];

  @override
  Future<SubmitDineInOrderResult> submit({
    required String submissionKey,
    required String tableSessionId,
    required List<DineInOrderItem> items,
    String customerNote = '',
    String? selectedRewardId,
    String? selectedCampaignId,
    String? guestDisplayName,
    List<String> submittedCartLineIds = const [],
  }) async {
    if (failingSubmissionKeys.contains(submissionKey)) {
      throw const SubmitDineInOrderException('unavailable', 'offline');
    }
    submittedKeys.add(submissionKey);
    return SubmitDineInOrderResult(
      orderId: 'order-$submissionKey',
      orderNumber: 'N-$submissionKey',
      duplicate: false,
    );
  }
}

PendingDineInSubmission _submission({
  required String submissionKey,
  String tableSessionId = 'table-session-1',
}) {
  return PendingDineInSubmission(
    submissionKey: submissionKey,
    tableSessionId: tableSessionId,
    items: const [
      {
        'kind': 'product',
        'productId': 'p1',
        'quantity': 1,
        'selectedModifiers': <Map<String, dynamic>>[],
        'note': '',
        'excludedIngredients': <String>[],
      },
    ],
    customerNote: '',
    queuedAt: DateTime.utc(2026, 11, 6, 9, 0),
  );
}

void main() {
  group('SyncOfflineDineInOrders', () {
    test('replays every queued submission and removes each on success',
        () async {
      final queueRepository = _InMemoryDineInOfflineOrderQueueRepository();
      await queueRepository.enqueue(_submission(submissionKey: 'key-1'));
      await queueRepository.enqueue(_submission(submissionKey: 'key-2'));
      final gateway = _FakeSubmitDineInOrderGateway();
      final sync = SyncOfflineDineInOrders(
        queueRepository: queueRepository,
        submitGateway: gateway,
      );

      final succeeded = await sync.call();

      expect(succeeded, 2);
      expect(gateway.submittedKeys, ['key-1', 'key-2']);
      expect(await queueRepository.findAll(), isEmpty);
    });

    test(
        'one entry failing (still offline/rejected) never blocks the rest, and stays queued',
        () async {
      final queueRepository = _InMemoryDineInOfflineOrderQueueRepository();
      await queueRepository.enqueue(_submission(submissionKey: 'key-ok-1'));
      await queueRepository.enqueue(_submission(submissionKey: 'key-fails'));
      await queueRepository.enqueue(_submission(submissionKey: 'key-ok-2'));
      final gateway = _FakeSubmitDineInOrderGateway(
        failingSubmissionKeys: {'key-fails'},
      );
      final sync = SyncOfflineDineInOrders(
        queueRepository: queueRepository,
        submitGateway: gateway,
      );

      final succeeded = await sync.call();

      expect(succeeded, 2);
      expect(gateway.submittedKeys, ['key-ok-1', 'key-ok-2']);
      final remaining = await queueRepository.findAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.submissionKey, 'key-fails');
    });

    test('an empty queue replays nothing and reports zero successes', () async {
      final queueRepository = _InMemoryDineInOfflineOrderQueueRepository();
      final gateway = _FakeSubmitDineInOrderGateway();
      final sync = SyncOfflineDineInOrders(
        queueRepository: queueRepository,
        submitGateway: gateway,
      );

      expect(await sync.call(), 0);
      expect(gateway.submittedKeys, isEmpty);
    });

    test('a bowl item in the queued payload is reconstructed correctly',
        () async {
      final queueRepository = _InMemoryDineInOfflineOrderQueueRepository();
      await queueRepository.enqueue(PendingDineInSubmission(
        submissionKey: 'key-bowl',
        tableSessionId: 'table-session-1',
        items: const [
          {
            'kind': 'bowl',
            'quantity': 2,
            'ingredientIds': ['pirinc', 'tavuk'],
            'note': 'az soslu',
          },
        ],
        customerNote: '',
        queuedAt: DateTime.utc(2026, 11, 6),
      ));
      final gateway = _FakeSubmitDineInOrderGateway();
      final sync = SyncOfflineDineInOrders(
        queueRepository: queueRepository,
        submitGateway: gateway,
      );

      final succeeded = await sync.call();

      expect(succeeded, 1);
      expect(gateway.submittedKeys, ['key-bowl']);
    });
  });
}
