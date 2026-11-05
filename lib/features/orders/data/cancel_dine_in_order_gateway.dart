import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';

/// What a successful `cancelMyPendingDineInOrder` call returns.
class CancelDineInOrderResult {
  final String orderId;
  final String status;
  final bool duplicate;

  const CancelDineInOrderResult({
    required this.orderId,
    required this.status,
    required this.duplicate,
  });
}

/// Thrown for an expected, non-exceptional-in-nature rejection — mirrors
/// the Cloud Function's own `HttpsError` codes verbatim, the same pattern
/// as `SubmitDineInOrderException`.
class CancelDineInOrderException implements Exception {
  final String code;
  final String message;

  const CancelDineInOrderException(this.code, this.message);

  @override
  String toString() => 'CancelDineInOrderException($code): $message';
}

/// Self-Order QR Faz 4 — the one client-facing boundary onto
/// `cancelMyPendingDineInOrder`, the first real, server-authoritative
/// dine-in order cancellation in this app. The caller's own ownership
/// (`guestAuthUid`) is verified server-side from `request.auth.uid` —
/// this gateway sends nothing but the order id.
///
/// Lives under `features/orders/data` (not `features/cart/data`, unlike
/// `SubmitDineInOrderGateway`) — mirrors `DineInCounterProposalGateway`'s
/// own placement: cancelling an already-created order is purely an
/// orders-lifecycle concern with no cart involvement, and `orders`
/// already depends on nothing in `cart`, so putting it there would be
/// this codebase's first feature-import cycle (`cart` already imports
/// `orders`' `OrderModel`/`ordersProvider`).
abstract interface class CancelDineInOrderGateway {
  Future<CancelDineInOrderResult> cancel({required String orderId});
}

class FirebaseCancelDineInOrderGateway implements CancelDineInOrderGateway {
  FirebaseCancelDineInOrderGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  @override
  Future<CancelDineInOrderResult> cancel({required String orderId}) async {
    final payload = {'orderId': orderId};
    // Mirrors `FirebaseSubmitDineInOrderGateway`'s own Windows REST bridge
    // — `cloud_functions` has no Windows plugin.
    final useRest = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    try {
      final data = useRest
          ? await _restClient.call('cancelMyPendingDineInOrder', payload)
          : (await functions.FirebaseFunctions.instance
                  .httpsCallable('cancelMyPendingDineInOrder')
                  .call<Map<String, dynamic>>(payload))
              .data;
      return CancelDineInOrderResult(
        orderId: data['orderId'] as String,
        status: data['status'] as String,
        duplicate: data['duplicate'] as bool,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw CancelDineInOrderException(
        error.code,
        error.message ?? 'Sipariş iptal edilemedi.',
      );
    } on RestCallableException catch (error) {
      throw CancelDineInOrderException(error.code, error.message);
    }
  }
}
