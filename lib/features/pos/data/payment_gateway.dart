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

class PaymentSubAccountAllocation {
  const PaymentSubAccountAllocation({
    required this.subAccountId,
    required this.payableAmountMinorUnits,
  });
  final String subAccountId;
  final int payableAmountMinorUnits;

  factory PaymentSubAccountAllocation.fromWire(Map<String, dynamic> data) {
    return PaymentSubAccountAllocation(
      subAccountId: data['subAccountId'] as String,
      payableAmountMinorUnits: data['payableAmountMinorUnits'] as int,
    );
  }
}

class PaymentIntentResult {
  const PaymentIntentResult({
    required this.intentId,
    required this.sessionId,
    required this.payableAmountMinorUnits,
    this.subAccountAllocations = const [],
  });
  final String intentId;
  final String sessionId;
  final int payableAmountMinorUnits;
  final List<PaymentSubAccountAllocation> subAccountAllocations;
}

/// One `paymentAttempts` doc as the checkout UI needs it — verbatim server
/// status/amounts, never re-derived client-side. See `PaymentGateway
/// .getPaymentSessionView`'s own doc comment: this is the canonical source
/// for "remaining amount," never a locally-accumulated tally.
class PaymentAttemptSummary {
  const PaymentAttemptSummary({
    required this.attemptId,
    required this.tenderType,
    required this.status,
    required this.amountMinorUnits,
    required this.declineReason,
  });
  final String attemptId;
  final String tenderType;
  final String status;
  final int amountMinorUnits;
  final String? declineReason;

  factory PaymentAttemptSummary.fromWire(Map<String, dynamic> data) {
    return PaymentAttemptSummary(
      attemptId: data['attemptId'] as String,
      tenderType: data['tenderType'] as String,
      status: data['status'] as String,
      amountMinorUnits: data['amountMinorUnits'] as int,
      declineReason: data['declineReason'] as String?,
    );
  }
}

class RefundRequestSummary {
  const RefundRequestSummary({
    required this.refundId,
    required this.refundType,
    required this.amountMinorUnits,
    required this.status,
  });
  final String refundId;
  final String refundType;
  final int amountMinorUnits;
  final String status;

  factory RefundRequestSummary.fromWire(Map<String, dynamic> data) {
    return RefundRequestSummary(
      refundId: data['refundId'] as String,
      refundType: data['refundType'] as String,
      amountMinorUnits: data['amountMinorUnits'] as int,
      status: data['status'] as String,
    );
  }
}

/// The checkout UI's canonical, server-authoritative snapshot — every
/// screen refresh re-fetches this rather than accumulating local state.
/// [exists] is `false` before `createPaymentIntent` has ever been called
/// for this check (a normal, expected state, not an error).
class PaymentSessionView {
  const PaymentSessionView({
    required this.exists,
    this.sessionId,
    this.sessionStatus,
    this.payableAmountMinorUnits,
    this.settledAmountMinorUnits,
    this.currencyCode,
    this.subAccountAllocations = const [],
    this.attempts = const [],
    this.refunds = const [],
  });

  final bool exists;
  final String? sessionId;

  /// Verbatim server status (`collecting`/`readyToComplete`/`completing`/
  /// `completed`/`cancelled`/`failed`) — never re-interpreted client-side.
  final String? sessionStatus;
  final int? payableAmountMinorUnits;
  final int? settledAmountMinorUnits;
  final String? currencyCode;
  final List<PaymentSubAccountAllocation> subAccountAllocations;
  final List<PaymentAttemptSummary> attempts;
  final List<RefundRequestSummary> refunds;

  /// The one figure the checkout UI's "Kalan" (remaining) display must
  /// always read from — never computed by subtracting locally-tracked
  /// tender amounts, which could drift from the canonical server state.
  int get remainingAmountMinorUnits =>
      (payableAmountMinorUnits ?? 0) - (settledAmountMinorUnits ?? 0);

  factory PaymentSessionView.fromWire(Map<String, dynamic> data) {
    if (data['exists'] != true) return const PaymentSessionView(exists: false);
    final intent = data['intent'] as Map<String, dynamic>?;
    return PaymentSessionView(
      exists: true,
      sessionId: data['sessionId'] as String,
      sessionStatus: data['sessionStatus'] as String,
      payableAmountMinorUnits: data['payableAmountMinorUnits'] as int,
      settledAmountMinorUnits: data['settledAmountMinorUnits'] as int,
      currencyCode: data['currencyCode'] as String,
      subAccountAllocations: [
        for (final raw
            in (intent?['subAccountAllocations'] as List? ?? const []))
          PaymentSubAccountAllocation.fromWire(
              Map<String, dynamic>.from(raw as Map)),
      ],
      attempts: [
        for (final raw in (data['attempts'] as List? ?? const []))
          PaymentAttemptSummary.fromWire(Map<String, dynamic>.from(raw as Map)),
      ],
      refunds: [
        for (final raw in (data['refunds'] as List? ?? const []))
          RefundRequestSummary.fromWire(Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }
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

  /// The checkout UI's canonical refresh point — call after EVERY tender/
  /// refund action, never accumulate "remaining" from local state alone.
  Future<PaymentSessionView> getPaymentSessionView({
    required PosDeviceContext ctx,
    required String checkId,
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
        subAccountAllocations: [
          for (final raw
              in (data['subAccountAllocations'] as List? ?? const []))
            PaymentSubAccountAllocation.fromWire(
                Map<String, dynamic>.from(raw as Map)),
        ],
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<PaymentSessionView> getPaymentSessionView({
    required PosDeviceContext ctx,
    required String checkId,
  }) async {
    try {
      final result = await _fn('getPaymentSessionOperationalView')
          .call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
      });
      return PaymentSessionView.fromWire(result.data);
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
  Future<PaymentSessionView> getPaymentSessionView({
    required PosDeviceContext ctx,
    required String checkId,
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
