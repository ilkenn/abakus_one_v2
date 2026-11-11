import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';

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

  /// Value equality (2026-11-03) — added so a `PosDeviceContext` can key a
  /// Riverpod `.family` provider (`topSellingProductsProvider`) correctly;
  /// nothing before this relied on identity semantics (confirmed by
  /// search), so this is purely additive.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PosDeviceContext &&
          other.organizationId == organizationId &&
          other.branchId == branchId &&
          other.deviceId == deviceId &&
          other.deviceSessionId == deviceSessionId);

  @override
  int get hashCode =>
      Object.hash(organizationId, branchId, deviceId, deviceSessionId);
}

class PosActionException implements Exception {
  const PosActionException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  @override
  String toString() => 'PosActionException($code): $message';
}

/// 2026-11-08 (ADR-066) — what `requestAcceptedLineCancellation` actually
/// did. A manager-tier caller's cancellation is [applied] immediately
/// (no [approvalRequestId]); a lower role's goes to remote approval and
/// stays pending until a manager approves it.
class AcceptedLineCancellationResult {
  const AcceptedLineCancellationResult({
    required this.cancellationRequestId,
    required this.applied,
    this.approvalRequestId,
  });

  final String cancellationRequestId;
  final bool applied;
  final String? approvalRequestId;
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

  /// 2026-11-11 — `reopenCheck`: `readyForPayment` → `open`, used when
  /// the payment dialog is closed without any payment so the table can keep
  /// ordering. The server refuses once payment activity has started.
  Future<void> reopenCheck({
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

  // --- Service requests (Dine-in Sprint 3) ------------------------------
  Future<void> resolveServiceRequest({
    required PosDeviceContext ctx,
    required String requestId,
  });

  // --- Accepted-line cancellation / financial adjustment (remote-approval-gated) ---
  Future<AcceptedLineCancellationResult> requestAcceptedLineCancellation({
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
  FirebasePosActionGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  bool get _useRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw PosActionException(
      error.code,
      error.message ?? 'İşlem gerçekleştirilemedi.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  /// 2026-10-29: routes through [RestCallableClient] on Windows — the same
  /// fix already applied to `FirebaseKitchenActionGateway`/
  /// `FirebaseTakeawayOrderResponseGateway`/`FirebaseDineInOrderResponseGateway`.
  /// `cloud_functions` ships no native Windows implementation at all, so
  /// every one of this gateway's callables previously threw the
  /// `CloudFunctionsHostApi.call` pigeon-channel error unconditionally on
  /// Windows desktop.
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (_useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw PosActionException(error.code, error.message);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> respondToOrderLines({
    required String orderId,
    required List<({int lineIndex, bool accept})> decisions,
  }) async {
    await _call('respondToDineInOrderLines', {
      'orderId': orderId,
      'decisions': [
        for (final d in decisions)
          {
            'lineIndex': d.lineIndex,
            'decision': d.accept ? 'accept' : 'reject',
          },
      ],
    });
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
    await _call('proposeDineInLineReplacement', {
      ...ctx.toWire(),
      'orderId': orderId,
      'lineIndex': lineIndex,
      'proposedProductId': proposedProductId,
      'proposedQuantity': proposedQuantity,
      'reasonCode': reasonCode,
      'reasonMessage': reasonMessage,
    });
  }

  @override
  Future<String> submitStaffEntryOrder({
    required PosDeviceContext ctx,
    required String tableId,
    required Map<String, dynamic> subAccountSelection,
    required List<Map<String, dynamic>> items,
  }) async {
    final result = await _call('submitDineInOrder', {
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
    return result['orderId'] as String;
  }

  @override
  Future<String> openCheck({
    required PosDeviceContext ctx,
    required String tableSessionId,
  }) async {
    final result = await _call('openCheck', {
      ...ctx.toWire(),
      'tableSessionId': tableSessionId,
    });
    return result['checkId'] as String;
  }

  @override
  Future<void> finalizeCheckReadyForPayment({
    required PosDeviceContext ctx,
    required String checkId,
  }) async {
    await _call('finalizeCheckReadyForPayment', {
      ...ctx.toWire(),
      'checkId': checkId,
    });
  }

  @override
  Future<void> reopenCheck({
    required PosDeviceContext ctx,
    required String checkId,
  }) async {
    await _call('reopenCheck', {
      ...ctx.toWire(),
      'checkId': checkId,
    });
  }

  @override
  Future<String> splitByProduct({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
    required String sourceOrderId,
    required int sourceLineIndex,
  }) async {
    final result = await _call('splitCheckByProduct', {
      ...ctx.toWire(),
      'checkId': checkId,
      'subAccountId': subAccountId,
      'sourceOrderId': sourceOrderId,
      'sourceLineIndex': sourceLineIndex,
    });
    return result['allocationId'] as String;
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
    final result = await _call('splitCheckByQuantity', {
      ...ctx.toWire(),
      'checkId': checkId,
      'subAccountId': subAccountId,
      'sourceOrderId': sourceOrderId,
      'sourceLineIndex': sourceLineIndex,
      'quantity': quantity,
    });
    return result['allocationId'] as String;
  }

  @override
  Future<String> splitByCustomer({
    required PosDeviceContext ctx,
    required String checkId,
    required String subAccountId,
  }) async {
    final result = await _call('splitCheckByCustomer', {
      ...ctx.toWire(),
      'checkId': checkId,
      'subAccountId': subAccountId,
    });
    return result['allocationId'] as String;
  }

  @override
  Future<List<String>> splitEqualByHeadcount({
    required PosDeviceContext ctx,
    required String checkId,
    required List<String> subAccountIds,
  }) async {
    final result = await _call('splitCheckEqualByHeadcount', {
      ...ctx.toWire(),
      'checkId': checkId,
      'subAccountIds': subAccountIds,
    });
    return List<String>.from(result['allocationIds'] as List);
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
    final result = await _call('splitCheckFreeAmount', {
      ...ctx.toWire(),
      'checkId': checkId,
      'subAccountId': subAccountId,
      'amountMinorUnits': amountMinorUnits,
      'sourceOrderId': sourceOrderId,
      'sourceLineIndex': sourceLineIndex,
    });
    return result['allocationId'] as String;
  }

  @override
  Future<void> transferTable({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async {
    await _call('transferTableSession', {
      ...ctx.toWire(),
      'sourceTableId': sourceTableId,
      'targetTableId': targetTableId,
    });
  }

  @override
  Future<void> mergeTables({
    required PosDeviceContext ctx,
    required String sourceTableId,
    required String targetTableId,
  }) async {
    await _call('mergeTableSessions', {
      ...ctx.toWire(),
      'sourceTableId': sourceTableId,
      'targetTableId': targetTableId,
    });
  }

  @override
  Future<void> resolveServiceRequest({
    required PosDeviceContext ctx,
    required String requestId,
  }) async {
    await _call('resolveServiceRequest', {
      ...ctx.toWire(),
      'requestId': requestId,
    });
  }

  @override
  Future<AcceptedLineCancellationResult> requestAcceptedLineCancellation({
    required PosDeviceContext ctx,
    required String orderId,
    required int lineIndex,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    final result = await _call('requestAcceptedLineCancellation', {
      ...ctx.toWire(),
      'orderId': orderId,
      'lineIndex': lineIndex,
      'reasonCode': reasonCode,
      'reasonMessage': reasonMessage,
    });
    // ADR-066 — `approvalRequestId` is null for a manager-direct
    // cancellation; `applied` is absent only from a pre-ADR-066 backend
    // (always remote approval then).
    return AcceptedLineCancellationResult(
      cancellationRequestId: result['cancellationRequestId'] as String? ?? '',
      applied: result['applied'] as bool? ?? false,
      approvalRequestId: result['approvalRequestId'] as String?,
    );
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
    final result = await _call('requestCheckFinancialAdjustment', {
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
    return result['approvalRequestId'] as String;
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
  Future<void> reopenCheck({
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
  Future<void> resolveServiceRequest({
    required PosDeviceContext ctx,
    required String requestId,
  }) async =>
      _unavailable();

  @override
  Future<AcceptedLineCancellationResult> requestAcceptedLineCancellation({
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
