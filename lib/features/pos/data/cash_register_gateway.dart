import 'package:cloud_functions/cloud_functions.dart' as functions;

import 'pos_action_gateway.dart' show PosDeviceContext;

/// The real cash register boundary — AP-4 Wave B/Wave D wiring. Mirrors
/// `pos_action_gateway.dart`'s exact contract shape against the real
/// callables in `functions/src/cashRegisterEngine.ts`.
class CashRegisterGatewayException implements Exception {
  const CashRegisterGatewayException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  @override
  String toString() => 'CashRegisterGatewayException($code): $message';
}

class CashSessionOpenResult {
  const CashSessionOpenResult({
    required this.sessionId,
    required this.status,
    this.approvalRequestId,
  });
  final String sessionId;

  /// `active` (manager on-site) or `awaitingOpenApproval` (remote) —
  /// verbatim server status, never re-interpreted client-side.
  final String status;
  final String? approvalRequestId;
}

class CashRequestResult {
  const CashRequestResult({
    required this.requestId,
    required this.status,
    required this.approvalRequestId,
  });
  final String requestId;
  final String status;
  final String approvalRequestId;
}

class CashCountResult {
  const CashCountResult({
    required this.countId,
    required this.expectedAmountMinorUnits,
    required this.varianceType,
    required this.varianceAmountMinorUnits,
    required this.approvalRequestId,
  });
  final String countId;
  final int expectedAmountMinorUnits;
  final String varianceType;
  final int varianceAmountMinorUnits;
  final String approvalRequestId;
}

abstract interface class CashRegisterGateway {
  Future<String> createCashDrawer({
    required PosDeviceContext ctx,
    required String name,
  });

  Future<CashSessionOpenResult> requestCashSessionOpen({
    required PosDeviceContext ctx,
    required String drawerId,
    required int openingFloatAmountMinorUnits,
    required String currencyCode,
    required String reason,
  });

  Future<CashRequestResult> requestCashMovement({
    required PosDeviceContext ctx,
    required String sessionId,
    required String movementType,
    required int amountMinorUnits,
    required String reason,
  });

  Future<CashRequestResult> requestCashAdjustment({
    required PosDeviceContext ctx,
    required String sessionId,
    required int amountMinorUnits,
    required String reason,
  });

  Future<CashCountResult> submitCashCount({
    required PosDeviceContext ctx,
    required String sessionId,
    required int actualAmountMinorUnits,
    String notes,
  });

  Future<void> closeCashSession({
    required PosDeviceContext ctx,
    required String sessionId,
  });
}

class FirebaseCashRegisterGateway implements CashRegisterGateway {
  const FirebaseCashRegisterGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw CashRegisterGatewayException(
      error.code,
      error.message ?? 'Kasa işlemi gerçekleştirilemedi.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  functions.HttpsCallable _fn(String name) =>
      functions.FirebaseFunctions.instance.httpsCallable(name);

  @override
  Future<String> createCashDrawer({
    required PosDeviceContext ctx,
    required String name,
  }) async {
    try {
      final result = await _fn('createCashDrawer').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'name': name,
      });
      return result.data['drawerId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<CashSessionOpenResult> requestCashSessionOpen({
    required PosDeviceContext ctx,
    required String drawerId,
    required int openingFloatAmountMinorUnits,
    required String currencyCode,
    required String reason,
  }) async {
    try {
      final result =
          await _fn('requestCashSessionOpen').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'drawerId': drawerId,
        'openingFloatAmountMinorUnits': openingFloatAmountMinorUnits,
        'currencyCode': currencyCode,
        'reason': reason,
      });
      final data = result.data;
      return CashSessionOpenResult(
        sessionId: data['sessionId'] as String,
        status: data['status'] as String,
        approvalRequestId: data['approvalRequestId'] as String?,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<CashRequestResult> requestCashMovement({
    required PosDeviceContext ctx,
    required String sessionId,
    required String movementType,
    required int amountMinorUnits,
    required String reason,
  }) async {
    try {
      final result =
          await _fn('requestCashMovement').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'sessionId': sessionId,
        'movementType': movementType,
        'amountMinorUnits': amountMinorUnits,
        'reason': reason,
      });
      final data = result.data;
      return CashRequestResult(
        requestId: data['requestId'] as String,
        status: data['status'] as String,
        approvalRequestId: data['approvalRequestId'] as String,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<CashRequestResult> requestCashAdjustment({
    required PosDeviceContext ctx,
    required String sessionId,
    required int amountMinorUnits,
    required String reason,
  }) async {
    try {
      final result =
          await _fn('requestCashAdjustment').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'sessionId': sessionId,
        'amountMinorUnits': amountMinorUnits,
        'reason': reason,
      });
      final data = result.data;
      return CashRequestResult(
        requestId: data['requestId'] as String,
        status: data['status'] as String,
        approvalRequestId: data['approvalRequestId'] as String,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<CashCountResult> submitCashCount({
    required PosDeviceContext ctx,
    required String sessionId,
    required int actualAmountMinorUnits,
    String notes = '',
  }) async {
    try {
      final result = await _fn('submitCashCount').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'sessionId': sessionId,
        'actualAmountMinorUnits': actualAmountMinorUnits,
        'notes': notes,
      });
      final data = result.data;
      final variance = data['variance'] as Map;
      return CashCountResult(
        countId: data['countId'] as String,
        expectedAmountMinorUnits: data['expectedAmountMinorUnits'] as int,
        varianceType: variance['type'] as String,
        varianceAmountMinorUnits: variance['amountMinorUnits'] as int,
        approvalRequestId: data['approvalRequestId'] as String,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> closeCashSession({
    required PosDeviceContext ctx,
    required String sessionId,
  }) async {
    try {
      await _fn('closeCashSession').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'sessionId': sessionId,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

/// Fail-closed fallback — mirrors `UnavailablePosActionGateway`.
class UnavailableCashRegisterGateway implements CashRegisterGateway {
  const UnavailableCashRegisterGateway();

  Never _unavailable() => throw const CashRegisterGatewayException(
        'unavailable',
        'Kasa sistemi şu anda kullanılamıyor.',
      );

  @override
  Future<String> createCashDrawer({
    required PosDeviceContext ctx,
    required String name,
  }) async =>
      _unavailable();

  @override
  Future<CashSessionOpenResult> requestCashSessionOpen({
    required PosDeviceContext ctx,
    required String drawerId,
    required int openingFloatAmountMinorUnits,
    required String currencyCode,
    required String reason,
  }) async =>
      _unavailable();

  @override
  Future<CashRequestResult> requestCashMovement({
    required PosDeviceContext ctx,
    required String sessionId,
    required String movementType,
    required int amountMinorUnits,
    required String reason,
  }) async =>
      _unavailable();

  @override
  Future<CashRequestResult> requestCashAdjustment({
    required PosDeviceContext ctx,
    required String sessionId,
    required int amountMinorUnits,
    required String reason,
  }) async =>
      _unavailable();

  @override
  Future<CashCountResult> submitCashCount({
    required PosDeviceContext ctx,
    required String sessionId,
    required int actualAmountMinorUnits,
    String notes = '',
  }) async =>
      _unavailable();

  @override
  Future<void> closeCashSession({
    required PosDeviceContext ctx,
    required String sessionId,
  }) async =>
      _unavailable();
}
