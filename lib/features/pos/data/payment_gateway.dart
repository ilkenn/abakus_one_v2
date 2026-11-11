import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';
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
    this.paymentMethodDisplayName,
    this.externalSlipNumber,
  });
  final String attemptId;
  final String tenderType;
  final String status;
  final int amountMinorUnits;
  final String? declineReason;

  /// 2026-11-11 — the meal-card brand ("Multinet") or "Kredi/Banka Kartı"
  /// for a payment recorded from an external terminal; `null` otherwise.
  final String? paymentMethodDisplayName;

  /// Optional slip / provision number typed from the external terminal.
  final String? externalSlipNumber;

  factory PaymentAttemptSummary.fromWire(Map<String, dynamic> data) {
    return PaymentAttemptSummary(
      attemptId: data['attemptId'] as String,
      tenderType: data['tenderType'] as String,
      status: data['status'] as String,
      amountMinorUnits: data['amountMinorUnits'] as int,
      declineReason: data['declineReason'] as String?,
      paymentMethodDisplayName: data['paymentMethodDisplayName'] as String?,
      externalSlipNumber: data['externalSlipNumber'] as String?,
    );
  }
}

/// 2026-11-11 — product owner: card and meal-card payments are taken on the
/// bank's / the provider's own physical terminal and only recorded on the
/// POS, where they settle immediately (`recordPaymentAttempt` with
/// `captureMode: "externalTerminal"`). [paymentMethodId] names the meal-card
/// brand (`pluxee`/`multinet`/`setcard`/`edenred`) and is `null` for a bank
/// card; [slipNumber] is optional.
class ExternalTerminalCapture {
  const ExternalTerminalCapture({this.paymentMethodId, this.slipNumber});

  final String? paymentMethodId;
  final String? slipNumber;

  Map<String, dynamic> toWire() {
    final slip = slipNumber?.trim();
    return {
      'captureMode': 'externalTerminal',
      if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
      if (slip != null && slip.isNotEmpty) 'externalSlipNumber': slip,
    };
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
    ExternalTerminalCapture? externalTerminal,
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
  FirebasePaymentGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw PaymentGatewayException(
      error.code,
      error.message ?? 'Ödeme işlemi gerçekleştirilemedi.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  /// 2026-10-30 — same Windows REST-callable bridge as `cash_register_
  /// gateway.dart`/`pos_action_gateway.dart` — `cloud_functions` has no
  /// Windows plugin implementation, so every call here previously hung
  /// indefinitely on Windows.
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final useRest = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw PaymentGatewayException(error.code, error.message);
      }
    }
    final callable = functions.FirebaseFunctions.instance.httpsCallable(name);
    try {
      final result = await callable.call<Map<String, dynamic>>(data);
      return result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<PaymentIntentResult> createPaymentIntent({
    required PosDeviceContext ctx,
    required String checkId,
    int coverCount = 0,
  }) async {
    final data = await _call('createPaymentIntent', {
      ...ctx.toWire(),
      'checkId': checkId,
      'coverCount': coverCount,
    });
    return PaymentIntentResult(
      intentId: data['intentId'] as String,
      sessionId: data['sessionId'] as String,
      payableAmountMinorUnits: data['payableAmountMinorUnits'] as int,
      subAccountAllocations: [
        for (final raw in (data['subAccountAllocations'] as List? ?? const []))
          PaymentSubAccountAllocation.fromWire(
              Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }

  @override
  Future<PaymentSessionView> getPaymentSessionView({
    required PosDeviceContext ctx,
    required String checkId,
  }) async {
    final data = await _call('getPaymentSessionOperationalView', {
      ...ctx.toWire(),
      'checkId': checkId,
    });
    return PaymentSessionView.fromWire(data);
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
    ExternalTerminalCapture? externalTerminal,
  }) async {
    final data = await _call('recordPaymentAttempt', {
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
      if (externalTerminal != null) ...externalTerminal.toWire(),
    });
    return PaymentAttemptResult(
      attemptId: data['attemptId'] as String,
      status: data['status'] as String,
      boncukUsed: data['boncukUsed'] as int?,
    );
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
    final data = await _call('requestPaymentRefund', {
      ...ctx.toWire(),
      'checkId': checkId,
      'refundType': refundType,
      'amountMinorUnits': amountMinorUnits,
      'reasonCode': reasonCode,
      'reasonMessage': reasonMessage,
      if (orderLineRefs != null) 'orderLineRefs': orderLineRefs,
    });
    return RefundRequestResult(
      refundId: data['refundId'] as String,
      status: data['status'] as String,
      approvalRequestId: data['approvalRequestId'] as String,
    );
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
    ExternalTerminalCapture? externalTerminal,
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
