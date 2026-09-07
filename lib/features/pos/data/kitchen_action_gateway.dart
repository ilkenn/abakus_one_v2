import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../domain/kds/kitchen_line_status.dart';

/// AP-5 Sprint 1 — the real backend boundary for kitchen work-item
/// transitions and the order-lifecycle advance that follows once every
/// work item for an order is ready. Deliberately **not** part of
/// [PosActionGateway]: that gateway's every method requires a live
/// trusted-device session context (`PosDeviceContext`); kitchen line
/// transitions are a staff+branch-authorized action only (mirrors
/// `PosAuthorizedAction.acknowledgeKitchenItem`'s own client-side
/// authorization, which has never required a device session either), so
/// folding them into `PosActionGateway` would silently violate that
/// class's own documented "every method is device-gated" contract.
class KitchenActionResult {
  const KitchenActionResult({
    required this.status,
    required this.revision,
    required this.allSiblingsReady,
    this.orderId,
    this.orderChannel,
  });

  final KitchenLineStatus status;
  final int revision;

  /// True only when [status] is [KitchenLineStatus.ready] and every other
  /// work item for the same order is also `ready` or `cancelled` — the
  /// server-computed signal `transitionKitchenWorkItem.ts` returns instead
  /// of this gateway (or the caller) re-deriving "is the whole order kitchen
  /// -ready" from a client-side read.
  final bool allSiblingsReady;

  /// Populated only when [allSiblingsReady] is true — the order to advance
  /// and its channel (`dineIn`/`takeaway`/`delivery`/`reservationPreorder`),
  /// so the caller knows which `advance*OrderStatus` callable to invoke
  /// next without needing its own copy of that mapping.
  final String? orderId;
  final String? orderChannel;
}

class KitchenActionException implements Exception {
  const KitchenActionException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'KitchenActionException($code): $message';
}

abstract interface class KitchenActionGateway {
  /// Transitions one [KitchenWorkItem] via the real, server-authoritative
  /// `transitionKitchenWorkItem` callable — the Firestore-backed
  /// replacement for the local `TransitionKitchenWorkItem` use case's
  /// `save()` call once Firebase is ready.
  Future<KitchenActionResult> transitionWorkItem({
    required String workItemId,
    required KitchenLineStatus to,
    required int expectedRevision,
    String? reason,
  });

  /// Advances the canonical order's own status — called by the KDS board
  /// only after [transitionWorkItem] returns `allSiblingsReady: true`,
  /// using the [channel]/[orderId] that same response carried. Dispatches
  /// to the already-real, already-tested per-channel callable
  /// (`advanceDineInOrderStatus`/`advanceTakeawayOrderStatus`/
  /// `advanceDeliveryOrderStatus`/`advanceReservationPreorderOrderStatus`)
  /// — never a new, parallel order-status write path.
  Future<void> advanceOrderStatus({
    required String orderId,
    required String channel,
    required String targetStatus,
  });
}

class FirebaseKitchenActionGateway implements KitchenActionGateway {
  const FirebaseKitchenActionGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw KitchenActionException(
      error.code,
      error.message ?? 'Mutfak işlemi gerçekleştirilemedi.',
    );
  }

  functions.HttpsCallable _fn(String name) =>
      functions.FirebaseFunctions.instance.httpsCallable(name);

  // AP-5 Sprint 2 fix: the real, stored `Order.channel` value for dine-in
  // is `'dineInQr'` (confirmed directly — every dine-in Cloud Function
  // checks `order.channel !== 'dineInQr'`), not `'dineIn'`. The Sprint 1
  // key was wrong and would have thrown `unknown-channel` for every real
  // dine-in order the moment `transitionKitchenWorkItem` returned it.
  static const Map<String, String> _advanceFunctionByChannel = {
    'dineInQr': 'advanceDineInOrderStatus',
    'takeaway': 'advanceTakeawayOrderStatus',
    'delivery': 'advanceDeliveryOrderStatus',
    'reservationPreorder': 'advanceReservationPreorderOrderStatus',
  };

  @override
  Future<KitchenActionResult> transitionWorkItem({
    required String workItemId,
    required KitchenLineStatus to,
    required int expectedRevision,
    String? reason,
  }) async {
    try {
      final result =
          await _fn('transitionKitchenWorkItem').call<Map<String, dynamic>>({
        'workItemId': workItemId,
        'to': to.name,
        'expectedRevision': expectedRevision,
        if (reason != null) 'reason': reason,
      });
      final data = result.data;
      return KitchenActionResult(
        status: KitchenLineStatus.values.byName(data['status'] as String),
        revision: data['revision'] as int,
        allSiblingsReady: data['allSiblingsReady'] as bool,
        orderId: data['orderId'] as String?,
        orderChannel: data['orderChannel'] as String?,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> advanceOrderStatus({
    required String orderId,
    required String channel,
    required String targetStatus,
  }) async {
    final functionName = _advanceFunctionByChannel[channel];
    if (functionName == null) {
      throw KitchenActionException(
        'unknown-channel',
        'Bilinmeyen sipariş kanalı: $channel',
      );
    }
    try {
      await _fn(functionName).call<Map<String, dynamic>>({
        'orderId': orderId,
        'targetStatus': targetStatus,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

class UnavailableKitchenActionGateway implements KitchenActionGateway {
  const UnavailableKitchenActionGateway();

  Never _unavailable() => throw const KitchenActionException(
        'unavailable',
        'Mutfak işlem servisi şu anda kullanılamıyor.',
      );

  @override
  Future<KitchenActionResult> transitionWorkItem({
    required String workItemId,
    required KitchenLineStatus to,
    required int expectedRevision,
    String? reason,
  }) async =>
      _unavailable();

  @override
  Future<void> advanceOrderStatus({
    required String orderId,
    required String channel,
    required String targetStatus,
  }) async =>
      _unavailable();
}
