import 'package:cloud_functions/cloud_functions.dart' as functions;

import 'pos_action_gateway.dart' show PosDeviceContext;

/// The real payment/tender/refund boundary — AP-4 Wave A/Wave D wiring.
/// Mirrors `pos_action_gateway.dart`'s exact contract shape (`PosDeviceContext`,
/// per-call `try`/`on FirebaseFunctionsException` rethrow, no parallel/
/// invented endpoint) against the real callables in
/// `functions/src/{paymentEngine,paymentRefund}.ts` — never a client-side
/// reimplementation of any money computation.
class PaymentGatewayException implements Exception {
  const PaymentGatewayException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  @override
  String toString() => 'PaymentGatewayException($code): $message';
}

class PaymentIntentResult {
  const PaymentIntentResult({
    required this.intentId,
    required this.sessionId,
    required this.payableAmountMinorUnits,
  });
  final String intentId;
  final String sessionId;
  final int payableAmountMinorUnits;
}

class PaymentAttemptResult {
  const PaymentAttemptResult({
    required this.attemptId,
    required this.status,
    this.boncukUsed,
  });
  final String attemptId;

  /// Verbatim server status string (`succeeded`/`declined`/`timedOut`/
  /// `providerPending`) — never re-interpreted client-side; the UI reads
  /// this directly rather than the client guessing at meaning.
  final String status;
  final int? boncukUsed;
}

class RefundRequestResult {
  const RefundRequestResult({
    required this.refundId,
    required this.status,
    required this.approvalRequestId,
  });
  final String refundId;
  final String status;
  final String approvalRequestId;
}

abstract interface class PaymentGateway {
  Future<PaymentIntentResult> createPaymentIntent({
    required PosDeviceContext ctx,
    required String checkId,
    int coverCount = 0,
  });

  Future<PaymentAttemptResult> recordPaymentAttempt({
    required PosDeviceContext ctx,
    required String checkId,
    required String sessionId,
    required String tenderType,
    required String idempotencyKey,
    required List<Map<String, dynamic>> allocations,
    int? requestedBoncukAmount,
    String? cashSessionId,
    ({String leaseId, int deviceSequence})? offlineLease,
  });

  Future<RefundRequestResult> requestPaymentRefund({
    required PosDeviceContext ctx,
    required String checkId,
    required String refundType,
    required int amountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
    List<String>? orderLineRefs,
  });
}

class FirebasePaymentGateway implements PaymentGateway {
  const FirebasePaymentGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw PaymentGatewayException(
      error.code,
      error.message ?? 'Ödeme işlemi gerçekleştirilemedi.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  functions.HttpsCallable _fn(String name) =>
      functions.FirebaseFunctions.instance.httpsCallable(name);

  @override
  Future<PaymentIntentResult> createPaymentIntent({
    required PosDeviceContext ctx,
    required String checkId,
    int coverCount = 0,
  }) async {
    try {
      final result =
          await _fn('createPaymentIntent').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
        'coverCount': coverCount,
      });
      final data = result.data;
      return PaymentIntentResult(
        intentId: data['intentId'] as String,
        sessionId: data['sessionId'] as String,
        payableAmountMinorUnits: data['payableAmountMinorUnits'] as int,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<PaymentAttemptResult> recordPaymentAttempt({
    required PosDeviceContext ctx,
    required String checkId,
    required String sessionId,
    required String tenderType,
    required String idempotencyKey,
    required List<Map<String, dynamic>> allocations,
    int? requestedBoncukAmount,
    String? cashSessionId,
    ({String leaseId, int deviceSequence})? offlineLease,
  }) async {
    try {
      final result =
          await _fn('recordPaymentAttempt').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
        'sessionId': sessionId,
        'tenderType': tenderType,
        'idempotencyKey': idempotencyKey,
        'allocations': allocations,
        if (requestedBoncukAmount != null)
          'requestedBoncukAmount': requestedBoncukAmount,
        if (cashSessionId != null) 'cashSessionId': cashSessionId,
        if (offlineLease != null)
          'offlineLease': {
            'leaseId': offlineLease.leaseId,
            'deviceSequence': offlineLease.deviceSequence,
          },
      });
      final data = result.data;
      return PaymentAttemptResult(
        attemptId: data['attemptId'] as String,
        status: data['status'] as String,
        boncukUsed: data['boncukUsed'] as int?,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<RefundRequestResult> requestPaymentRefund({
    required PosDeviceContext ctx,
    required String checkId,
    required String refundType,
    required int amountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
    List<String>? orderLineRefs,
  }) async {
    try {
      final result =
          await _fn('requestPaymentRefund').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
        'refundType': refundType,
        'amountMinorUnits': amountMinorUnits,
        'reasonCode': reasonCode,
        'reasonMessage': reasonMessage,
        if (orderLineRefs != null) 'orderLineRefs': orderLineRefs,
      });
      final data = result.data;
      return RefundRequestResult(
        refundId: data['refundId'] as String,
        status: data['status'] as String,
        approvalRequestId: data['approvalRequestId'] as String,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

/// Fail-closed fallback — mirrors `UnavailablePosActionGateway`'s own
/// reasoning exactly: selected whenever Firebase isn't ready, never
/// silently substitutes a mock/in-memory result for real money movement.
class UnavailablePaymentGateway implements PaymentGateway {
  const UnavailablePaymentGateway();

  Never _unavailable() => throw const PaymentGatewayException(
        'unavailable',
        'Ödeme sistemi şu anda kullanılamıyor.',
      );

  @override
  Future<PaymentIntentResult> createPaymentIntent({
    required PosDeviceContext ctx,
    required String checkId,
    int coverCount = 0,
  }) async =>
      _unavailable();

  @override
  Future<PaymentAttemptResult> recordPaymentAttempt({
    required PosDeviceContext ctx,
    required String checkId,
    required String sessionId,
    required String tenderType,
    required String idempotencyKey,
    required List<Map<String, dynamic>> allocations,
    int? requestedBoncukAmount,
    String? cashSessionId,
    ({String leaseId, int deviceSequence})? offlineLease,
  }) async =>
      _unavailable();

  @override
  Future<RefundRequestResult> requestPaymentRefund({
    required PosDeviceContext ctx,
    required String checkId,
    required String refundType,
    required int amountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
    List<String>? orderLineRefs,
  }) async =>
      _unavailable();
}
