import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';

/// 2026-10-28 — the real backend boundary for accepting/rejecting a
/// `pendingConfirmation` takeaway order, mirroring `KitchenActionGateway`'s
/// exact shape. **The missing step this closes**: a new order (any
/// channel) always starts `pendingConfirmation` and is only ever
/// Kitchen-visible once `confirmed` — `respondToTakeawayOrder` (the real,
/// already-built Cloud Function) was the one callable with zero client
/// callers anywhere in this app, confirmed by a direct repo-wide search —
/// so a takeaway order placed through the real POS flow could never
/// reach KDS at all, not because of any query/sync bug.
///
/// **2026-10-29**: now routes through [RestCallableClient] on Windows —
/// this previously called `functions.FirebaseFunctions.instance
/// .httpsCallable(...)` unconditionally on every platform, the exact
/// native-plugin path confirmed broken on Windows desktop (`cloud_functions`
/// ships no native Windows implementation at all — see
/// `StaffClaimsSyncClient.syncAndRefresh`'s identical, already-fixed gap).
/// Not yet reported for this specific gateway, fixed proactively rather
/// than waiting for the same class of bug to surface a second time.
class TakeawayOrderResponseException implements Exception {
  const TakeawayOrderResponseException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'TakeawayOrderResponseException($code): $message';
}

/// Mirrors `respondToTakeawayOrder.ts`'s own `TAKEAWAY_REJECTION_REASON_CODES`
/// exactly — never invented independently.
enum TakeawayRejectionReasonCode {
  itemUnavailable,
  kitchenUnavailable,
  capacityUnavailable,
  operationalIssue,
  other,
}

abstract interface class TakeawayOrderResponseGateway {
  /// Accepts [orderId] — transitions `pendingConfirmation` -> `confirmed`,
  /// which is what makes `acceptOrderLine.ts` materialize the real
  /// `kitchenWorkItems` the KDS board reads.
  Future<void> confirm({required String orderId});

  /// Rejects [orderId] before ever accepting it — transitions
  /// `pendingConfirmation` -> `rejected`. Never used for a previously-
  /// accepted order (that's `cancelTakeawayOrderForStaff`, a distinct,
  /// separate action this gateway deliberately does not expose).
  Future<void> reject({
    required String orderId,
    required TakeawayRejectionReasonCode reasonCode,
    String? reasonMessage,
  });
}

class FirebaseTakeawayOrderResponseGateway
    implements TakeawayOrderResponseGateway {
  FirebaseTakeawayOrderResponseGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw TakeawayOrderResponseException(
      error.code,
      error.message ?? 'Sipariş işlemi gerçekleştirilemedi.',
    );
  }

  Future<void> _respond({
    required String orderId,
    required String decision,
    String? reasonCode,
    String? reasonMessage,
  }) async {
    final data = {
      'orderId': orderId,
      'decision': decision,
      if (reasonCode != null) 'reasonCode': reasonCode,
      if (reasonMessage != null) 'reasonMessage': reasonMessage,
    };
    final useRest = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (useRest) {
      try {
        await _restClient.call('respondToTakeawayOrder', data);
      } on RestCallableException catch (error) {
        throw TakeawayOrderResponseException(error.code, error.message);
      }
      return;
    }
    try {
      await functions.FirebaseFunctions.instance
          .httpsCallable('respondToTakeawayOrder')
          .call<Map<String, dynamic>>(data);
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> confirm({required String orderId}) =>
      _respond(orderId: orderId, decision: 'confirm');

  @override
  Future<void> reject({
    required String orderId,
    required TakeawayRejectionReasonCode reasonCode,
    String? reasonMessage,
  }) =>
      _respond(
        orderId: orderId,
        decision: 'reject',
        reasonCode: reasonCode.name,
        reasonMessage: reasonMessage,
      );
}

/// Fail-closed pre-Firebase fallback — mirrors
/// `UnavailableKitchenActionGateway`'s exact shape.
class UnavailableTakeawayOrderResponseGateway
    implements TakeawayOrderResponseGateway {
  const UnavailableTakeawayOrderResponseGateway();

  Never _unavailable() => throw const TakeawayOrderResponseException(
        'unavailable',
        'Sipariş yanıt servisi şu anda kullanılamıyor.',
      );

  @override
  Future<void> confirm({required String orderId}) async => _unavailable();

  @override
  Future<void> reject({
    required String orderId,
    required TakeawayRejectionReasonCode reasonCode,
    String? reasonMessage,
  }) async =>
      _unavailable();
}
