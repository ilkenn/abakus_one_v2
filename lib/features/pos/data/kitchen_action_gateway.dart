import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';
import '../domain/kds/kitchen_line_status.dart';

/// 2026-10-29 — mirrors `dineInOrderLifecycle.ts`'s own
/// `DINE_IN_CANCELLATION_REASON_CODES` exactly, never invented
/// independently. Only meaningful for an already-`confirmed` (or later)
/// dine-in order — `advanceDineInOrderStatus` is the one callable that
/// accepts `targetStatus: 'cancelled'` with one of these codes.
///
/// 2026-11-08 — also the reason vocabulary for [KitchenActionGateway
/// .cancelOrder] on every other channel: takeaway/delivery/reservation-
/// preorder's own `*_CANCELLATION_REASON_CODES` are identical except
/// `customerNoShow` in place of [guestLeft] — the gateway maps that one
/// value onto the wire, so the KDS needs only this one closed set.
enum DineInCancellationReasonCode {
  itemUnavailable,
  kitchenUnavailable,
  capacityUnavailable,
  guestLeft,
  operationalIssue,
  other,
}

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
  /// using the [channel]/[orderId] that same response carried, OR directly
  /// by a staff-initiated whole-order cancel (`targetStatus: 'cancelled'`,
  /// [reasonCode] then required — see
  /// `dineInOrderLifecycle.ts`'s `DINE_IN_CANCELLATION_REASON_CODES`).
  /// Dispatches to the already-real, already-tested per-channel callable
  /// (`advanceDineInOrderStatus`/`advanceTakeawayOrderStatus`/
  /// `advanceDeliveryOrderStatus`/`advanceReservationPreorderOrderStatus`)
  /// — never a new, parallel order-status write path.
  Future<void> advanceOrderStatus({
    required String orderId,
    required String channel,
    required String targetStatus,
    String? reasonCode,
    String? reasonMessage,
  });

  /// 2026-11-08 — the KDS card's whole-order "İptal Et", for every channel
  /// that has a staff cancellation callable: `dineInQr` via
  /// `advanceDineInOrderStatus` (`targetStatus: 'cancelled'`), and
  /// `takeaway`/`delivery`/`reservationPreorder` via their own dedicated
  /// `cancel*OrderForStaff` callables — each server-side callable still
  /// enforces its own permission tier (e.g. manager-only once a takeaway
  /// order is `preparing`).
  Future<void> cancelOrder({
    required String orderId,
    required String channel,
    required DineInCancellationReasonCode reasonCode,
    String? reasonMessage,
  });
}

class FirebaseKitchenActionGateway implements KitchenActionGateway {
  FirebaseKitchenActionGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  bool get _useRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw KitchenActionException(
      error.code,
      error.message ?? 'Mutfak işlemi gerçekleştirilemedi.',
    );
  }

  /// **2026-10-29**: now routes through [RestCallableClient] on Windows —
  /// this previously called `functions.FirebaseFunctions.instance
  /// .httpsCallable(...)` unconditionally, the exact native-plugin path
  /// confirmed broken on Windows desktop (`cloud_functions` ships no
  /// native Windows implementation at all) — the real cause of the
  /// reported `CloudFunctionsHostApi.call` pigeon-channel error on every
  /// KDS status-transition attempt.
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (_useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw KitchenActionException(error.code, error.message);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

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
    final data = await _call('transitionKitchenWorkItem', {
      'workItemId': workItemId,
      'to': to.name,
      'expectedRevision': expectedRevision,
      if (reason != null) 'reason': reason,
    });
    return KitchenActionResult(
      status: KitchenLineStatus.values.byName(data['status'] as String),
      revision: data['revision'] as int,
      allSiblingsReady: data['allSiblingsReady'] as bool,
      orderId: data['orderId'] as String?,
      orderChannel: data['orderChannel'] as String?,
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
    final functionName = _advanceFunctionByChannel[channel];
    if (functionName == null) {
      throw KitchenActionException(
        'unknown-channel',
        'Bilinmeyen sipariş kanalı: $channel',
      );
    }
    await _call(functionName, {
      'orderId': orderId,
      'targetStatus': targetStatus,
      if (reasonCode != null) 'reasonCode': reasonCode,
      if (reasonMessage != null) 'reasonMessage': reasonMessage,
    });
  }

  static const Map<String, String> _staffCancelFunctionByChannel = {
    'takeaway': 'cancelTakeawayOrderForStaff',
    'delivery': 'cancelDeliveryOrderForStaff',
    'reservationPreorder': 'cancelReservationPreorderOrderForStaff',
  };

  /// `guestLeft` is dine-in's own wording; every other channel's server
  /// enum spells the same concept `customerNoShow`.
  static String _cancellationReasonWireValue(
    DineInCancellationReasonCode code,
    String channel,
  ) {
    if (code == DineInCancellationReasonCode.guestLeft &&
        channel != 'dineInQr') {
      return 'customerNoShow';
    }
    return code.name;
  }

  @override
  Future<void> cancelOrder({
    required String orderId,
    required String channel,
    required DineInCancellationReasonCode reasonCode,
    String? reasonMessage,
  }) async {
    final wireReason = _cancellationReasonWireValue(reasonCode, channel);
    if (channel == 'dineInQr') {
      await advanceOrderStatus(
        orderId: orderId,
        channel: channel,
        targetStatus: 'cancelled',
        reasonCode: wireReason,
        reasonMessage: reasonMessage,
      );
      return;
    }
    final functionName = _staffCancelFunctionByChannel[channel];
    if (functionName == null) {
      throw KitchenActionException(
        'unknown-channel',
        'Bilinmeyen sipariş kanalı: $channel',
      );
    }
    await _call(functionName, {
      'orderId': orderId,
      'reasonCode': wireReason,
      if (reasonMessage != null) 'reasonMessage': reasonMessage,
    });
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
    String? reasonCode,
    String? reasonMessage,
  }) async =>
      _unavailable();

  @override
  Future<void> cancelOrder({
    required String orderId,
    required String channel,
    required DineInCancellationReasonCode reasonCode,
    String? reasonMessage,
  }) async =>
      _unavailable();
}
