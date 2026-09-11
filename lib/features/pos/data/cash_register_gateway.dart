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

class CashOpenSessionSummary {
  const CashOpenSessionSummary({required this.sessionId, required this.status});
  final String sessionId;
  final String status;

  factory CashOpenSessionSummary.fromWire(Map<String, dynamic> data) {
    return CashOpenSessionSummary(
      sessionId: data['sessionId'] as String,
      status: data['status'] as String,
    );
  }
}

class CashDrawerSummary {
  const CashDrawerSummary({
    required this.drawerId,
    required this.name,
    required this.isActive,
    this.openSession,
  });
  final String drawerId;
  final String name;
  final bool isActive;
  final CashOpenSessionSummary? openSession;

  factory CashDrawerSummary.fromWire(Map<String, dynamic> data) {
    final openSessionRaw = data['openSession'] as Map<String, dynamic>?;
    return CashDrawerSummary(
      drawerId: data['drawerId'] as String,
      name: data['name'] as String,
      isActive: data['isActive'] as bool,
      openSession: openSessionRaw != null
          ? CashOpenSessionSummary.fromWire(openSessionRaw)
          : null,
    );
  }
}

class CashMovementSummary {
  const CashMovementSummary({
    required this.type,
    required this.amountMinorUnits,
    required this.reason,
    required this.timestamp,
  });
  final String type;
  final int amountMinorUnits;
  final String reason;
  final DateTime timestamp;

  factory CashMovementSummary.fromWire(Map<String, dynamic> data) {
    return CashMovementSummary(
      type: data['type'] as String,
      amountMinorUnits: data['amountMinorUnits'] as int,
      reason: data['reason'] as String,
      timestamp: DateTime.parse(data['timestamp'] as String),
    );
  }
}

class CashVarianceSummary {
  const CashVarianceSummary(
      {required this.type, required this.amountMinorUnits});
  final String type;
  final int amountMinorUnits;

  factory CashVarianceSummary.fromWire(Map<String, dynamic> data) {
    return CashVarianceSummary(
      type: data['type'] as String,
      amountMinorUnits: data['amountMinorUnits'] as int,
    );
  }
}

class CashCountSummary {
  const CashCountSummary({
    required this.countId,
    required this.expectedAmountMinorUnits,
    required this.actualAmountMinorUnits,
    required this.variance,
    required this.declaredAt,
  });
  final String countId;
  final int expectedAmountMinorUnits;
  final int actualAmountMinorUnits;
  final CashVarianceSummary variance;
  final DateTime declaredAt;

  factory CashCountSummary.fromWire(Map<String, dynamic> data) {
    return CashCountSummary(
      countId: data['countId'] as String,
      expectedAmountMinorUnits: data['expectedAmountMinorUnits'] as int,
      actualAmountMinorUnits: data['actualAmountMinorUnits'] as int,
      variance: CashVarianceSummary.fromWire(
          Map<String, dynamic>.from(data['variance'] as Map)),
      declaredAt: DateTime.parse(data['declaredAt'] as String),
    );
  }
}

class CashReconciliationSummary {
  const CashReconciliationSummary({
    required this.status,
    required this.varianceAccepted,
    required this.variance,
  });
  final String status;
  final bool varianceAccepted;
  final CashVarianceSummary variance;

  factory CashReconciliationSummary.fromWire(Map<String, dynamic> data) {
    return CashReconciliationSummary(
      status: data['status'] as String,
      varianceAccepted: data['varianceAccepted'] as bool,
      variance: CashVarianceSummary.fromWire(
          Map<String, dynamic>.from(data['variance'] as Map)),
    );
  }
}

/// The cash screen's canonical, server-authoritative snapshot — [exists]
/// is `false` for a `sessionId` that was never created or belongs to a
/// different org/branch.
class CashSessionView {
  const CashSessionView({
    required this.exists,
    this.sessionId,
    this.drawerId,
    this.status,
    this.businessDate,
    this.openingFloatAmountMinorUnits,
    this.settledAmountMinorUnits,
    this.currencyCode,
    this.cashRegisterModel,
    this.movements = const [],
    this.counts = const [],
    this.reconciliations = const [],
  });

  final bool exists;
  final String? sessionId;
  final String? drawerId;

  /// Verbatim server status (`awaitingOpenApproval`/`openRejected`/
  /// `active`/`pendingApproval`/`approved`/`rejected`/`closed`) — never
  /// re-interpreted client-side.
  final String? status;
  final String? businessDate;
  final int? openingFloatAmountMinorUnits;
  final int? settledAmountMinorUnits;
  final String? currencyCode;
  final String? cashRegisterModel;
  final List<CashMovementSummary> movements;
  final List<CashCountSummary> counts;
  final List<CashReconciliationSummary> reconciliations;

  factory CashSessionView.fromWire(Map<String, dynamic> data) {
    if (data['exists'] != true) return const CashSessionView(exists: false);
    return CashSessionView(
      exists: true,
      sessionId: data['sessionId'] as String,
      drawerId: data['drawerId'] as String,
      status: data['status'] as String,
      businessDate: data['businessDate'] as String,
      openingFloatAmountMinorUnits: data['openingFloatAmountMinorUnits'] as int,
      settledAmountMinorUnits: data['settledAmountMinorUnits'] as int,
      currencyCode: data['currencyCode'] as String,
      cashRegisterModel: data['cashRegisterModel'] as String,
      movements: [
        for (final raw in (data['movements'] as List? ?? const []))
          CashMovementSummary.fromWire(Map<String, dynamic>.from(raw as Map)),
      ],
      counts: [
        for (final raw in (data['counts'] as List? ?? const []))
          CashCountSummary.fromWire(Map<String, dynamic>.from(raw as Map)),
      ],
      reconciliations: [
        for (final raw in (data['reconciliations'] as List? ?? const []))
          CashReconciliationSummary.fromWire(
              Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }
}

/// Gün Sonu — Nakit/Kredi Kartı/Diğer revenue breakdown for one cash
/// session's lifetime (since it opened), server-computed. Mirrors
/// `functions/src/cashRegisterEngine.ts`'s `getDailyRevenueSummary` response
/// exactly.
class DailyRevenueSummary {
  const DailyRevenueSummary({
    required this.sessionId,
    required this.currencyCode,
    required this.cashMinorUnits,
    required this.cardMinorUnits,
    required this.otherMinorUnits,
    required this.totalMinorUnits,
  });

  final String sessionId;
  final String currencyCode;
  final int cashMinorUnits;
  final int cardMinorUnits;
  final int otherMinorUnits;
  final int totalMinorUnits;

  factory DailyRevenueSummary.fromWire(Map<String, dynamic> data) {
    return DailyRevenueSummary(
      sessionId: data['sessionId'] as String,
      currencyCode: data['currencyCode'] as String,
      cashMinorUnits: data['cashMinorUnits'] as int,
      cardMinorUnits: data['cardMinorUnits'] as int,
      otherMinorUnits: data['otherMinorUnits'] as int,
      totalMinorUnits: data['totalMinorUnits'] as int,
    );
  }
}

abstract interface class CashRegisterGateway {
  Future<String> createCashDrawer({
    required PosDeviceContext ctx,
    required String name,
  });

  Future<List<CashDrawerSummary>> listCashDrawers({
    required PosDeviceContext ctx,
  });

  /// The cash screen's canonical refresh point — call after EVERY action,
  /// never accumulate movements/status from local state alone.
  Future<CashSessionView> getCashSessionView({
    required PosDeviceContext ctx,
    required String sessionId,
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

  Future<DailyRevenueSummary> getDailyRevenueSummary({
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
  Future<List<CashDrawerSummary>> listCashDrawers({
    required PosDeviceContext ctx,
  }) async {
    try {
      final result = await _fn('listCashDrawers').call<Map<String, dynamic>>({
        ...ctx.toWire(),
      });
      return [
        for (final raw in (result.data['drawers'] as List))
          CashDrawerSummary.fromWire(Map<String, dynamic>.from(raw as Map)),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<CashSessionView> getCashSessionView({
    required PosDeviceContext ctx,
    required String sessionId,
  }) async {
    try {
      final result = await _fn('getCashSessionOperationalView')
          .call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'sessionId': sessionId,
      });
      return CashSessionView.fromWire(result.data);
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

  @override
  Future<DailyRevenueSummary> getDailyRevenueSummary({
    required PosDeviceContext ctx,
    required String sessionId,
  }) async {
    try {
      final result = await _fn('getDailyRevenueSummary').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'sessionId': sessionId,
      });
      return DailyRevenueSummary.fromWire(result.data);
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
  Future<List<CashDrawerSummary>> listCashDrawers({
    required PosDeviceContext ctx,
  }) async =>
      _unavailable();

  @override
  Future<CashSessionView> getCashSessionView({
    required PosDeviceContext ctx,
    required String sessionId,
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

  @override
  Future<DailyRevenueSummary> getDailyRevenueSummary({
    required PosDeviceContext ctx,
    required String sessionId,
  }) async =>
      _unavailable();
}
