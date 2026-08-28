import 'package:cloud_functions/cloud_functions.dart' as functions;

/// The device-gated POS mutation boundary — AP-3 continuation. Every
/// method requires the caller's own live trusted-device session context
/// (`organizationId`/`branchId`/`deviceId`/`deviceSessionId`) — this
/// gateway never re-derives or caches that context itself; the caller
/// (`PosTableWorkspaceController`) obtains it fresh from
/// `TrustedDeviceSessionController.ensureFreshSession()` before every
/// action. Mirrors every real callable's exact existing contract
/// (`functions/src/{checkOperations,submitDineInOrder,
/// respondToDineInOrderLines,dineInCounterProposal,tableSessionTransfer}.ts`)
/// — no parallel/invented endpoint anywhere in this file.
class PosDeviceContext {
  const PosDeviceContext({
    required this.organizationId,
    required this.branchId,
    required this.deviceId,
    required this.deviceSessionId,
  });

  final String organizationId;
  final String branchId;
  final String deviceId;
  final String deviceSessionId;

  Map<String, dynamic> toWire() => {
        'organizationId': organizationId,
        'branchId': branchId,
        'deviceId': deviceId,
        'deviceSessionId': deviceSessionId,
      };
}

class PosActionException implements Exception {
  const PosActionException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  @override
  String toString() => 'PosActionException($code): $message';
}

abstract interface class PosActionGateway {
  // --- Line decisions (guestSession-mode orders only) ------------------
  Future<void> respondToOrderLines({
    required String orderId,
    required List<({int lineIndex, bool accept})> decisions,
  });

  Future<void> proposeLineReplacement({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String proposedProductId,
    required int proposedQuantity,
    required String reasonCode,
    required String reasonMessage,
  });

  // --- Staff order entry -------------------------------------------------
  Future<String> submitStaffEntryOrder({
    required PosDeviceContext ctx,
    required String tableId,
    required Map<String, dynamic> subAccountSelection,
    required List<Map<String, dynamic>> items,
  });

  // --- Check lifecycle -----------------------------------------------
  Future<String> openCheck({
    required PosDeviceContext ctx,
    required String tableSessionId,
  });

  Future<void> finalizeCheckReadyForPayment({
    required PosDeviceContext ctx,
    required String checkId,
  });

  // --- Splits --------------------------------------------------------
  Future<String> splitByProduct({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
  });

  Future<String> splitByQuantity({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
    required int quantity,
  });

  Future<String> splitByCustomer({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
  });

  Future<List<String>> splitEqualByHeadcount({
    required PosDeviceContext ctx,
    required String checkId,
    required List<String> subAccountIds,
  });

  Future<String> splitFreeAmount({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required int amountMinorUnits,
    required String sourceOrderId,
    required int sourceLineIndex,
  });

  // --- Table transfer/merge -------------------------------------------
  Future<void> transferTable({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  });

  Future<void> mergeTables({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  });

  // --- Accepted-line cancellation / financial adjustment (remote-approval-gated) ---
  Future<String> requestAcceptedLineCancellation({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String reasonCode,
    required String reasonMessage,
  });

  Future<String> requestCheckFinancialAdjustment({
    required PosDeviceContext ctx,
    required String checkId,
    required String scope,
    String? allocationId,
    String? subAccountId,
    required String adjustmentType,
    int? percentageBasisPoints,
    int? fixedAmountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
  });
}

class FirebasePosActionGateway implements PosActionGateway {
  const FirebasePosActionGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw PosActionException(
      error.code,
      error.message ?? 'İşlem gerçekleştirilemedi.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  functions.HttpsCallable _fn(String name) =>
      functions.FirebaseFunctions.instance.httpsCallable(name);

  @override
  Future<void> respondToOrderLines({
    required String orderId,
    required List<({int lineIndex, bool accept})> decisions,
  }) async {
    try {
      await _fn('respondToDineInOrderLines').call<Map<String, dynamic>>({
        'orderId': orderId,
        'decisions': [
          for (final d in decisions)
            {
              'lineIndex': d.lineIndex,
              'decision': d.accept ? 'accept' : 'reject',
            },
        ],
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> proposeLineReplacement({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String proposedProductId,
    required int proposedQuantity,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    try {
      await _fn('proposeDineInLineReplacement').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'orderId': orderId,
        'lineIndex': lineIndex,
        'proposedProductId': proposedProductId,
        'proposedQuantity': proposedQuantity,
        'reasonCode': reasonCode,
        'reasonMessage': reasonMessage,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<String> submitStaffEntryOrder({
    required PosDeviceContext ctx,
    required String tableId,
    required Map<String, dynamic> subAccountSelection,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final result = await _fn('submitDineInOrder').call<Map<String, dynamic>>({
        'mode': 'staffEntry',
        'submissionKey': DateTime.now().microsecondsSinceEpoch.toString(),
        'organizationId': ctx.organizationId,
        'branchId': ctx.branchId,
        'tableId': tableId,
        'deviceId': ctx.deviceId,
        'deviceSessionId': ctx.deviceSessionId,
        'subAccountSelection': subAccountSelection,
        'items': items,
      });
      return result.data['orderId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<String> openCheck({
    required PosDeviceContext ctx,
    required String tableSessionId,
  }) async {
    try {
      final result = await _fn('openCheck').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'tableSessionId': tableSessionId,
      });
      return result.data['checkId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> finalizeCheckReadyForPayment({
    required PosDeviceContext ctx,
    required String checkId,
  }) async {
    try {
      await _fn('finalizeCheckReadyForPayment').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<String> splitByProduct({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
  }) async {
    try {
      final result =
          await _fn('splitCheckByProduct').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
        'subAccountId': subAccountId,
        'sourceOrderId': sourceOrderId,
        'sourceLineIndex': sourceLineIndex,
      });
      return result.data['allocationId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<String> splitByQuantity({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
    required int quantity,
  }) async {
    try {
      final result =
          await _fn('splitCheckByQuantity').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
        'subAccountId': subAccountId,
        'sourceOrderId': sourceOrderId,
        'sourceLineIndex': sourceLineIndex,
        'quantity': quantity,
      });
      return result.data['allocationId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<String> splitByCustomer({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
  }) async {
    try {
      final result =
          await _fn('splitCheckByCustomer').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
        'subAccountId': subAccountId,
      });
      return result.data['allocationId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<String>> splitEqualByHeadcount({
    required PosDeviceContext ctx,
    required String checkId,
    required List<String> subAccountIds,
  }) async {
    try {
      final result =
          await _fn('splitCheckEqualByHeadcount').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
        'subAccountIds': subAccountIds,
      });
      return List<String>.from(result.data['allocationIds'] as List);
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<String> splitFreeAmount({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required int amountMinorUnits,
    required String sourceOrderId,
    required int sourceLineIndex,
  }) async {
    try {
      final result =
          await _fn('splitCheckFreeAmount').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
        'subAccountId': subAccountId,
        'amountMinorUnits': amountMinorUnits,
        'sourceOrderId': sourceOrderId,
        'sourceLineIndex': sourceLineIndex,
      });
      return result.data['allocationId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> transferTable({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async {
    try {
      await _fn('transferTableSession').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'sourceTableId': sourceTableId,
        'targetTableId': targetTableId,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> mergeTables({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async {
    try {
      await _fn('mergeTableSessions').call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'sourceTableId': sourceTableId,
        'targetTableId': targetTableId,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<String> requestAcceptedLineCancellation({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    try {
      final result = await _fn('requestAcceptedLineCancellation')
          .call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'orderId': orderId,
        'lineIndex': lineIndex,
        'reasonCode': reasonCode,
        'reasonMessage': reasonMessage,
      });
      return result.data['approvalRequestId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<String> requestCheckFinancialAdjustment({
    required PosDeviceContext ctx,
    required String checkId,
    required String scope,
    String? allocationId,
    String? subAccountId,
    required String adjustmentType,
    int? percentageBasisPoints,
    int? fixedAmountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    try {
      final result = await _fn('requestCheckFinancialAdjustment')
          .call<Map<String, dynamic>>({
        ...ctx.toWire(),
        'checkId': checkId,
        'scope': scope,
        if (allocationId != null) 'allocationId': allocationId,
        if (subAccountId != null) 'subAccountId': subAccountId,
        'adjustmentType': adjustmentType,
        if (percentageBasisPoints != null)
          'percentageBasisPoints': percentageBasisPoints,
        if (fixedAmountMinorUnits != null)
          'fixedAmountMinorUnits': fixedAmountMinorUnits,
        'reasonCode': reasonCode,
        'reasonMessage': reasonMessage,
      });
      return result.data['approvalRequestId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

class UnavailablePosActionGateway implements PosActionGateway {
  const UnavailablePosActionGateway();

  Never _unavailable() => throw const PosActionException(
        'unavailable',
        'POS işlem servisi şu anda kullanılamıyor.',
      );

  @override
  Future<void> respondToOrderLines({
    required String orderId,
    required List<({int lineIndex, bool accept})> decisions,
  }) async =>
      _unavailable();

  @override
  Future<void> proposeLineReplacement({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String proposedProductId,
    required int proposedQuantity,
    required String reasonCode,
    required String reasonMessage,
  }) async =>
      _unavailable();

  @override
  Future<String> submitStaffEntryOrder({
    required PosDeviceContext ctx,
    required String tableId,
    required Map<String, dynamic> subAccountSelection,
    required List<Map<String, dynamic>> items,
  }) async =>
      _unavailable();

  @override
  Future<String> openCheck({
    required PosDeviceContext ctx,
    required String tableSessionId,
  }) async =>
      _unavailable();

  @override
  Future<void> finalizeCheckReadyForPayment({
    required PosDeviceContext ctx,
    required String checkId,
  }) async =>
      _unavailable();

  @override
  Future<String> splitByProduct({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
  }) async =>
      _unavailable();

  @override
  Future<String> splitByQuantity({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
    required int quantity,
  }) async =>
      _unavailable();

  @override
  Future<String> splitByCustomer({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
  }) async =>
      _unavailable();

  @override
  Future<List<String>> splitEqualByHeadcount({
    required PosDeviceContext ctx,
    required String checkId,
    required List<String> subAccountIds,
  }) async =>
      _unavailable();

  @override
  Future<String> splitFreeAmount({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required int amountMinorUnits,
    required String sourceOrderId,
    required int sourceLineIndex,
  }) async =>
      _unavailable();

  @override
  Future<void> transferTable({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async =>
      _unavailable();

  @override
  Future<void> mergeTables({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async =>
      _unavailable();

  @override
  Future<String> requestAcceptedLineCancellation({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String reasonCode,
    required String reasonMessage,
  }) async =>
      _unavailable();

  @override
  Future<String> requestCheckFinancialAdjustment({
    required PosDeviceContext ctx,
    required String checkId,
    required String scope,
    String? allocationId,
    String? subAccountId,
    required String adjustmentType,
    int? percentageBasisPoints,
    int? fixedAmountMinorUnits,
    required String reasonCode,
    required String reasonMessage,
  }) async =>
      _unavailable();
}
