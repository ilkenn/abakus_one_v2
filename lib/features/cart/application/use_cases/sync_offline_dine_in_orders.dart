import '../../data/dine_in_offline_order_queue_repository.dart';
import '../../data/submit_dine_in_order_gateway.dart';

/// Replays every queued [PendingDineInSubmission] through the real
/// `submitDineInOrder` gateway — Self-Order QR Faz 6. Each entry's own
/// `submissionKey` is already globally idempotent server-side (the exact
/// mechanism `submitDineInOrder.ts` uses to detect/dedupe a retried
/// request), so entries are replayed independently, in any order — never
/// a strict-sequence replay like the POS offline-payment outbox needs.
///
/// One entry failing (still offline, or a genuine server rejection) never
/// blocks the rest — each is attempted on its own, and a failure simply
/// leaves that one entry queued for the next sync attempt.
class SyncOfflineDineInOrders {
  const SyncOfflineDineInOrders({
    required this.queueRepository,
    required this.submitGateway,
  });

  final DineInOfflineOrderQueueRepository queueRepository;
  final SubmitDineInOrderGateway submitGateway;

  /// Returns how many entries were successfully submitted (and removed
  /// from the queue) this call.
  Future<int> call() async {
    final pending = await queueRepository.findAll();
    var succeeded = 0;
    for (final submission in pending) {
      try {
        await submitGateway.submit(
          submissionKey: submission.submissionKey,
          tableSessionId: submission.tableSessionId,
          items: [for (final json in submission.items) _itemFromJson(json)],
          customerNote: submission.customerNote,
          selectedRewardId: submission.selectedRewardId,
          selectedCampaignId: submission.selectedCampaignId,
          guestDisplayName: submission.guestDisplayName,
          submittedCartLineIds: submission.submittedCartLineIds,
        );
        await queueRepository.remove(submission.submissionKey);
        succeeded += 1;
      } catch (_) {
        // Left queued — disclosed, deliberate: a genuinely-still-offline
        // device, or a transient server error, both deserve another
        // attempt at the next reconnect/poll, never a silently dropped
        // order.
      }
    }
    return succeeded;
  }

  DineInOrderItem _itemFromJson(Map<String, dynamic> json) {
    if (json['kind'] == 'bowl') {
      return DineInBowlItem(
        quantity: json['quantity'] as int,
        ingredientIds: (json['ingredientIds'] as List).cast<String>(),
        note: json['note'] as String? ?? '',
      );
    }
    return DineInProductItem(
      productId: json['productId'] as String,
      quantity: json['quantity'] as int,
      selectedModifiers: [
        for (final m in (json['selectedModifiers'] as List? ?? const []))
          (
            groupId: (m as Map)['groupId'] as String,
            optionId: m['optionId'] as String,
          ),
      ],
      note: json['note'] as String? ?? '',
      excludedIngredients:
          (json['excludedIngredients'] as List? ?? const []).cast<String>(),
    );
  }
}
