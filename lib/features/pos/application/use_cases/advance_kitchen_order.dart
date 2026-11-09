import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_status.dart';
import '../../data/kitchen_action_gateway.dart';
import '../../domain/kds/kitchen_line_status.dart';
import '../../domain/kds/kitchen_order_action_policy.dart';
import '../../domain/kds/kitchen_work_item.dart';

/// 2026-11-08 — sequences the real KDS backend calls so the canonical
/// order's status always walks the backend's strict
/// `confirmed -> preparing -> ready -> (served | completed)` chain one
/// exact step at a time.
///
/// The bug this closes: kitchen work items (lines) and the order itself are
/// tracked separately. The board used to move lines along and then, once
/// every line was ready, ask for the order's `confirmed -> ready` — but
/// nothing had ever advanced the order to `preparing`, so every
/// `advance*OrderStatus` callable rejected it ("only the exact next status
/// is allowed, no skipping").
///
/// Not atomic across calls (each is its own server transaction). Every
/// backend step is idempotent for a repeated same-status request
/// (`duplicate: true`) and every line step re-reads nothing client-side
/// beyond the revision the previous step returned — so a partial failure
/// is recovered simply by pressing the same action again.
class AdvanceKitchenOrder {
  const AdvanceKitchenOrder({required KitchenActionGateway gateway})
      : _gateway = gateway;

  final KitchenActionGateway _gateway;

  /// "Hazırlanıyor": the order `confirmed -> preparing`, then every
  /// not-yet-started line of [workItems] to `preparing`.
  Future<void> startPreparing({
    required String orderId,
    required OrderChannel channel,
    required List<KitchenWorkItem> workItems,
  }) async {
    await _advanceOrder(orderId, channel, OrderStatus.preparing);
    for (final item in workItems) {
      await _stepLineTowards(item, KitchenLineStatus.preparing);
    }
  }

  /// "Hazırlandı": guarantees `preparing` first (if the order is still
  /// [currentStatus] `confirmed`), moves every still-active line of
  /// [workItems] to `ready`, then the order `preparing -> ready`.
  Future<void> markReady({
    required String orderId,
    required OrderChannel channel,
    required OrderStatus currentStatus,
    required List<KitchenWorkItem> workItems,
  }) async {
    if (currentStatus == OrderStatus.confirmed) {
      await _advanceOrder(orderId, channel, OrderStatus.preparing);
    }
    for (final item in workItems) {
      await _stepLineTowards(item, KitchenLineStatus.ready);
    }
    await _advanceOrder(orderId, channel, OrderStatus.ready);
  }

  /// "Teslim Edildi": `ready -> served` (dine-in/reservation) or
  /// `ready -> completed` (takeaway). Delivery is deliberately refused —
  /// its next step is a courier hand-off, not a kitchen action.
  Future<void> handOver({
    required String orderId,
    required OrderChannel channel,
  }) async {
    final target = KitchenOrderActionPolicy.handOverTargetFor(channel);
    if (target == null) {
      throw const KitchenActionException(
        'unsupported-channel',
        'Bu siparişin teslimi mutfak ekranından yapılamaz.',
      );
    }
    await _advanceOrder(orderId, channel, target);
  }

  Future<void> cancel({
    required String orderId,
    required OrderChannel channel,
    required DineInCancellationReasonCode reasonCode,
    String? reasonMessage,
  }) async {
    _requireSupported(channel);
    await _gateway.cancelOrder(
      orderId: orderId,
      channel: channel.name,
      reasonCode: reasonCode,
      reasonMessage: reasonMessage,
    );
  }

  /// Called after a single line's own transition (a tap on one line, from
  /// the board or the detail screen) so the order keeps pace with it:
  /// - a line starting preparation moves a still-`confirmed` order to
  ///   `preparing`;
  /// - the last line becoming ready ([allSiblingsReady], server-computed)
  ///   moves the order to `ready` — through `preparing` first if needed,
  ///   never the rejected `confirmed -> ready` skip.
  Future<void> syncOrderAfterLineTransition({
    required String orderId,
    required OrderChannel channel,
    required OrderStatus? currentStatus,
    required KitchenLineStatus lineTarget,
    required bool allSiblingsReady,
  }) async {
    if (!KitchenOrderActionPolicy.supportsOrderActions(channel)) return;
    final needsPreparing = currentStatus == OrderStatus.confirmed;
    if (allSiblingsReady) {
      if (needsPreparing) {
        await _advanceOrder(orderId, channel, OrderStatus.preparing);
      }
      await _advanceOrder(orderId, channel, OrderStatus.ready);
      return;
    }
    if (lineTarget == KitchenLineStatus.preparing && needsPreparing) {
      await _advanceOrder(orderId, channel, OrderStatus.preparing);
    }
  }

  void _requireSupported(OrderChannel channel) {
    if (!KitchenOrderActionPolicy.supportsOrderActions(channel)) {
      throw const KitchenActionException(
        'unsupported-channel',
        'Bu sipariş kanalı için mutfak işlemi desteklenmiyor.',
      );
    }
  }

  Future<void> _advanceOrder(
    String orderId,
    OrderChannel channel,
    OrderStatus target,
  ) {
    _requireSupported(channel);
    return _gateway.advanceOrderStatus(
      orderId: orderId,
      channel: channel.name,
      targetStatus: target.name,
    );
  }

  /// Walks one line forward through the backend's own line state machine
  /// (`queued -> acknowledged -> preparing -> ready`, `recalled ->
  /// preparing`) until it reaches [target] — each step carrying the
  /// revision the previous step returned. Lines already at/after [target]
  /// or terminal (cancelled/unavailable/wasted) are left untouched.
  Future<void> _stepLineTowards(
    KitchenWorkItem item,
    KitchenLineStatus target,
  ) async {
    var status = item.status;
    var revision = item.revision;
    while (status != target) {
      final next = _nextStepTowards(status, target);
      if (next == null) return;
      final result = await _gateway.transitionWorkItem(
        workItemId: item.id,
        to: next,
        expectedRevision: revision,
      );
      status = result.status;
      revision = result.revision;
    }
  }

  static KitchenLineStatus? _nextStepTowards(
    KitchenLineStatus from,
    KitchenLineStatus target,
  ) {
    switch (from) {
      case KitchenLineStatus.queued:
        return KitchenLineStatus.acknowledged;
      case KitchenLineStatus.acknowledged:
      case KitchenLineStatus.recalled:
        return KitchenLineStatus.preparing;
      case KitchenLineStatus.preparing:
        return target == KitchenLineStatus.ready
            ? KitchenLineStatus.ready
            : null;
      case KitchenLineStatus.ready:
      case KitchenLineStatus.cancelled:
      case KitchenLineStatus.unavailable:
      case KitchenLineStatus.wasted:
        return null;
    }
  }
}
