import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';

/// 2026-10-29 — the real backend boundary for accepting/rejecting a
/// `pendingConfirmation` dine-in (table QR) order from the Admin Siparişler
/// screen, mirroring `TakeawayOrderResponseGateway`'s exact shape and
/// Windows REST-bridge handling.
///
/// **Two real, independent backend mechanisms, composed here into one
/// "Onayla" action** (found by reading both callables directly, not
/// assumed): a `guestSession`-mode dine-in order's lines start
/// `pendingApproval` — only `respondToDineInOrderLines` accepting them
/// actually materializes `kitchenWorkItems` (what makes the order
/// KDS-visible at all). Separately, `advanceDineInOrderStatus` is what
/// moves the order's own `status` field off `pendingConfirmation` (what the
/// Admin Siparişler list's "Onay Bekliyor" label reads). Neither callable
/// triggers the other — `advanceDineInOrderStatus`'s own doc comment is
/// explicit that writing `status` is "all this callable ever needs to do."
/// [confirm] calls both, in that order, so a single staff tap does what the
/// takeaway flow's own single `respondToTakeawayOrder` call already does in
/// one step. [reject] only needs `advanceDineInOrderStatus` — rejecting
/// before ever accepting any line needs no kitchen-side cleanup.
class DineInOrderResponseException implements Exception {
  const DineInOrderResponseException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'DineInOrderResponseException($code): $message';
}

/// Mirrors `dineInOrderLifecycle.ts`'s own `DINE_IN_REJECTION_REASON_CODES`
/// exactly — never invented independently.
enum DineInRejectionReasonCode {
  itemUnavailable,
  kitchenUnavailable,
  capacityUnavailable,
  operationalIssue,
  other,
}

abstract interface class DineInOrderResponseGateway {
  /// Accepts every currently-`pendingApproval` line at [pendingLineIndexes]
  /// (via `respondToDineInOrderLines`, which materializes the real
  /// `kitchenWorkItems` the KDS board reads), then advances the order's own
  /// `status` `pendingConfirmation` -> `confirmed` (via
  /// `advanceDineInOrderStatus`). A `staffEntry`-mode order (whose lines are
  /// never `pendingApproval` in the first place) should pass an empty
  /// [pendingLineIndexes] — this skips straight to the status advance.
  Future<void> confirm({
    required String orderId,
    required List<int> pendingLineIndexes,
  });

  /// Rejects [orderId] before ever accepting it — transitions
  /// `pendingConfirmation` -> `rejected` via `advanceDineInOrderStatus`.
  /// Never used for a previously-confirmed order (that's a `cancelled`
  /// transition, a distinct, separate action this gateway deliberately
  /// does not expose).
  Future<void> reject({
    required String orderId,
    required DineInRejectionReasonCode reasonCode,
    String? reasonMessage,
  });
}

class FirebaseDineInOrderResponseGateway implements DineInOrderResponseGateway {
  FirebaseDineInOrderResponseGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  bool get _useRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Never _rethrowFunctions(functions.FirebaseFunctionsException error) {
    throw DineInOrderResponseException(
      error.code,
      error.message ?? 'Sipariş işlemi gerçekleştirilemedi.',
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (_useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw DineInOrderResponseException(error.code, error.message);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrowFunctions(error);
    }
  }

  @override
  Future<void> confirm({
    required String orderId,
    required List<int> pendingLineIndexes,
  }) async {
    if (pendingLineIndexes.isNotEmpty) {
      await _call('respondToDineInOrderLines', {
        'orderId': orderId,
        'decisions': [
          for (final lineIndex in pendingLineIndexes)
            {'lineIndex': lineIndex, 'decision': 'accept'},
        ],
      });
    }
    await _call('advanceDineInOrderStatus', {
      'orderId': orderId,
      'targetStatus': 'confirmed',
    });
  }

  @override
  Future<void> reject({
    required String orderId,
    required DineInRejectionReasonCode reasonCode,
    String? reasonMessage,
  }) async {
    await _call('advanceDineInOrderStatus', {
      'orderId': orderId,
      'targetStatus': 'rejected',
      'reasonCode': reasonCode.name,
      if (reasonMessage != null) 'reasonMessage': reasonMessage,
    });
  }
}

/// Fail-closed pre-Firebase fallback — mirrors
/// `UnavailableTakeawayOrderResponseGateway`'s exact shape.
class UnavailableDineInOrderResponseGateway
    implements DineInOrderResponseGateway {
  const UnavailableDineInOrderResponseGateway();

  Never _unavailable() => throw const DineInOrderResponseException(
        'unavailable',
        'Sipariş yanıt servisi şu anda kullanılamıyor.',
      );

  @override
  Future<void> confirm({
    required String orderId,
    required List<int> pendingLineIndexes,
  }) async =>
      _unavailable();

  @override
  Future<void> reject({
    required String orderId,
    required DineInRejectionReasonCode reasonCode,
    String? reasonMessage,
  }) async =>
      _unavailable();
}
