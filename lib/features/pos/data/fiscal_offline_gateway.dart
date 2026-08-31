import 'package:cloud_functions/cloud_functions.dart' as functions;

import 'pos_action_gateway.dart' show PosDeviceContext;

/// The real fiscal operation + offline authorization lease boundary —
/// AP-4 Wave C/Wave D wiring. Mirrors `pos_action_gateway.dart`'s exact
/// contract shape against the real callables in
/// `functions/src/fiscalEngine.ts`. No PAX A910SF/GMP-3 vendor protocol
/// detail is referenced anywhere in this file — see
/// `docs/ap4_wave_c_vendor_dependencies.md`.
class FiscalOfflineGatewayException implements Exception {
  const FiscalOfflineGatewayException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  @override
  String toString() => 'FiscalOfflineGatewayException($code): $message';
}

class FiscalOperationResult {
  const FiscalOperationResult({required this.entryId, required this.status});
  final String entryId;

  /// Verbatim server status (`succeeded`/`declined`/`timedOut`/
  /// `unavailable`) — never re-interpreted client-side.
  final String status;
}

class IssuedOfflineLease {
  const IssuedOfflineLease({
    required this.leaseId,
    required this.expiresAt,
    required this.allowedTenderTypes,
    required this.maxTransactionCount,
    required this.maxTransactionValueMinorUnits,
    required this.catalogVersion,
  });
  final String leaseId;
  final DateTime expiresAt;
  final List<String> allowedTenderTypes;
  final int maxTransactionCount;
  final int maxTransactionValueMinorUnits;
  final String catalogVersion;
}

abstract interface class FiscalOfflineGateway {
  Future<FiscalOperationResult> recordFiscalOperation({
    required PosDeviceContext ctx,
    required String operationType,
    required int amountMinorUnits,
    required String currencyCode,
    required String idempotencyKey,
    String? checkId,
    String? paymentAttemptId,
    String? refundRequestId,
    String? cashSessionId,
  });

  Future<IssuedOfflineLease> issueOfflineLease({
    required PosDeviceContext ctx,
    int? validityMinutes,
    int? maxTransactionCount,
    int? maxTransactionValueMinorUnits,
  });

  Future<void> revokeOfflineLease({
    required String organizationId,
    required String branchId,
    required String leaseId,
    required String reason,
  });
}

class FirebaseFiscalOfflineGateway implements FiscalOfflineGateway {
  const FirebaseFiscalOfflineGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw FiscalOfflineGatewayException(
      error.code,
      error.message ?? 'Fiskal işlem gerçekleştirilemedi.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  functions.HttpsCallable _fn(String name) =>
      functions.FirebaseFunctions.instance.httpsCallable(name);

  @override
  Future<FiscalOperationResult> recordFiscalOperation({
    required PosDeviceContext ctx,
    required String operationType,
    required int amountMinorUnits,
    required String currencyCode,
    required String idempotencyKey,
    String? checkId,
    String? paymentAttemptId,
    String? refundRequestId,
    String? cashSessionId,
  }) async {
    try {
      final result =
          await _fn('recordFiscalOperation').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'operationType': operationType,
        'amountMinorUnits': amountMinorUnits,
        'currencyCode': currencyCode,
        'idempotencyKey': idempotencyKey,
        if (checkId != null) 'checkId': checkId,
        if (paymentAttemptId != null) 'paymentAttemptId': paymentAttemptId,
        if (refundRequestId != null) 'refundRequestId': refundRequestId,
        if (cashSessionId != null) 'cashSessionId': cashSessionId,
      });
      final data = result.data;
      return FiscalOperationResult(
        entryId: data['entryId'] as String,
        status: data['status'] as String,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<IssuedOfflineLease> issueOfflineLease({
    required PosDeviceContext ctx,
    int? validityMinutes,
    int? maxTransactionCount,
    int? maxTransactionValueMinorUnits,
  }) async {
    try {
      final result = await _fn('issueOfflineLease').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        if (validityMinutes != null) 'validityMinutes': validityMinutes,
        if (maxTransactionCount != null)
          'maxTransactionCount': maxTransactionCount,
        if (maxTransactionValueMinorUnits != null)
          'maxTransactionValueMinorUnits': maxTransactionValueMinorUnits,
      });
      final data = result.data;
      return IssuedOfflineLease(
        leaseId: data['leaseId'] as String,
        expiresAt: DateTime.parse(data['expiresAt'] as String),
        allowedTenderTypes:
            List<String>.from(data['allowedTenderTypes'] as List),
        maxTransactionCount: data['maxTransactionCount'] as int,
        maxTransactionValueMinorUnits:
            data['maxTransactionValueMinorUnits'] as int,
        catalogVersion: data['catalogVersion'] as String,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> revokeOfflineLease({
    required String organizationId,
    required String branchId,
    required String leaseId,
    required String reason,
  }) async {
    try {
      await _fn('revokeOfflineLease').call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'leaseId': leaseId,
        'reason': reason,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

/// Fail-closed fallback — mirrors `UnavailablePosActionGateway`. Consistent
/// with the locked offline rule: if the backend that would ISSUE a lease is
/// unreachable, no lease can be minted client-side under any circumstance.
class UnavailableFiscalOfflineGateway implements FiscalOfflineGateway {
  const UnavailableFiscalOfflineGateway();

  Never _unavailable() => throw const FiscalOfflineGatewayException(
        'unavailable',
        'Fiskal/çevrimdışı yetkilendirme sistemi şu anda kullanılamıyor.',
      );

  @override
  Future<FiscalOperationResult> recordFiscalOperation({
    required PosDeviceContext ctx,
    required String operationType,
    required int amountMinorUnits,
    required String currencyCode,
    required String idempotencyKey,
    String? checkId,
    String? paymentAttemptId,
    String? refundRequestId,
    String? cashSessionId,
  }) async =>
      _unavailable();

  @override
  Future<IssuedOfflineLease> issueOfflineLease({
    required PosDeviceContext ctx,
    int? validityMinutes,
    int? maxTransactionCount,
    int? maxTransactionValueMinorUnits,
  }) async =>
      _unavailable();

  @override
  Future<void> revokeOfflineLease({
    required String organizationId,
    required String branchId,
    required String leaseId,
    required String reason,
  }) async =>
      _unavailable();
}
