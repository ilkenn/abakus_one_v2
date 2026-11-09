import 'package:abakus_one_v2/features/pos/data/kitchen_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';

/// Records every call, in order, as a compact string so tests can assert
/// the exact backend call sequence:
/// - `line:<workItemId>-><status>@<expectedRevision>`
/// - `order:<orderId>/<channel>-><targetStatus>`
/// - `cancel:<orderId>/<channel>/<reasonCode>`
///
/// A line transition always succeeds with `revision = expectedRevision + 1`;
/// [allSiblingsReady] is what it reports for a transition to `ready`.
/// [failOrderTargetStatus], when set, makes an `advanceOrderStatus` call to
/// that status throw the backend's real "no skipping" rejection.
class RecordingKitchenActionGateway implements KitchenActionGateway {
  RecordingKitchenActionGateway({
    this.allSiblingsReady = false,
    this.failOrderTargetStatus,
  });

  final bool allSiblingsReady;
  final String? failOrderTargetStatus;
  final List<String> calls = [];

  @override
  Future<KitchenActionResult> transitionWorkItem({
    required String workItemId,
    required KitchenLineStatus to,
    required int expectedRevision,
    String? reason,
  }) async {
    calls.add('line:$workItemId->${to.name}@$expectedRevision');
    return KitchenActionResult(
      status: to,
      revision: expectedRevision + 1,
      allSiblingsReady: to == KitchenLineStatus.ready && allSiblingsReady,
    );
  }

  @override
  Future<void> advanceOrderStatus({
    required String orderId,
    required String channel,
    required String targetStatus,
    String? reasonCode,
    String? reasonMessage,
  }) async {
    calls.add('order:$orderId/$channel->$targetStatus');
    if (targetStatus == failOrderTargetStatus) {
      throw const KitchenActionException(
        'failed-precondition',
        'Sipariş durumu güncellenemedi.',
      );
    }
  }

  @override
  Future<void> cancelOrder({
    required String orderId,
    required String channel,
    required DineInCancellationReasonCode reasonCode,
    String? reasonMessage,
  }) async {
    calls.add('cancel:$orderId/$channel/${reasonCode.name}');
  }
}
