import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../domain/financial/admin_financial_summaries.dart';

/// Mirrors `AdminReservationException`'s exact shape
/// (`admin_reservation_gateway.dart`) — deliberately duplicated rather than
/// imported, matching that file's own stated reasoning: each Admin
/// sub-surface owns its error type rather than sharing one across
/// unrelated data layers.
class AdminFinancialException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  const AdminFinancialException(this.code, this.message, [this.details]);

  @override
  String toString() => 'AdminFinancialException($code): $message';
}

/// AP-4 Wave D — the real, branch-wide read boundary onto
/// `functions/src/adminFinancialView.ts`'s five callables. Read-only by
/// design (mirrors `AdminReservationGateway`'s narrow interface shape) —
/// every mutation Admin needs (refund/cash/fiscal actions) already goes
/// through the POS-side gateways (`PaymentGateway`/`CashRegisterGateway`/
/// `FiscalOfflineGateway`) or the remote-approval flow, never duplicated
/// here.
abstract interface class AdminFinancialGateway {
  Future<List<AdminPaymentSessionSummary>> listPaymentSessionsForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  });

  Future<List<AdminRefundSummary>> listRefundsForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  });

  Future<List<AdminCashSessionSummary>> listCashSessionsForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  });

  Future<List<AdminFiscalOperationSummary>> listFiscalOperationsForBranch({
    required String organizationId,
    required String branchId,
    bool onlyUnresolved = false,
    int pageSize = 50,
  });

  Future<List<AdminOfflineLeaseSummary>> listOfflineLeasesForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  });
}

class FirebaseAdminFinancialGateway implements AdminFinancialGateway {
  const FirebaseAdminFinancialGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw AdminFinancialException(
      error.code,
      error.message ?? 'İşlem tamamlanamadı.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  List<Map<String, dynamic>> _rawList(Map<String, dynamic> data, String key) {
    return List<Map<String, dynamic>>.from(
      (data[key] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  @override
  Future<List<AdminPaymentSessionSummary>> listPaymentSessionsForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('listPaymentSessionsForBranch');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'pageSize': pageSize,
      });
      return [
        for (final s in _rawList(result.data, 'sessions'))
          AdminPaymentSessionSummary(
            sessionId: s['sessionId'] as String,
            checkId: s['checkId'] as String,
            status: s['status'] as String,
            payableAmountMinorUnits: s['payableAmountMinorUnits'] as int,
            settledAmountMinorUnits: s['settledAmountMinorUnits'] as int,
            currencyCode: s['currencyCode'] as String,
            createdAt: DateTime.parse(s['createdAt'] as String),
          ),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<AdminRefundSummary>> listRefundsForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('listRefundsForBranch');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'pageSize': pageSize,
      });
      return [
        for (final r in _rawList(result.data, 'refunds'))
          AdminRefundSummary(
            refundId: r['refundId'] as String,
            checkId: r['checkId'] as String,
            refundType: r['refundType'] as String,
            amountMinorUnits: r['amountMinorUnits'] as int,
            status: r['status'] as String,
            reasonCode: r['reasonCode'] as String,
            createdAt: DateTime.parse(r['createdAt'] as String),
          ),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<AdminCashSessionSummary>> listCashSessionsForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('listCashSessionsForBranch');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'pageSize': pageSize,
      });
      return [
        for (final s in _rawList(result.data, 'sessions'))
          AdminCashSessionSummary(
            sessionId: s['sessionId'] as String,
            drawerId: s['drawerId'] as String,
            status: s['status'] as String,
            businessDate: s['businessDate'] as String,
            openingFloatAmountMinorUnits:
                s['openingFloatAmountMinorUnits'] as int,
            settledAmountMinorUnits: s['settledAmountMinorUnits'] as int,
            currencyCode: s['currencyCode'] as String,
            createdAt: DateTime.parse(s['createdAt'] as String),
          ),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<AdminFiscalOperationSummary>> listFiscalOperationsForBranch({
    required String organizationId,
    required String branchId,
    bool onlyUnresolved = false,
    int pageSize = 50,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('listFiscalOperationsForBranch');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'onlyUnresolved': onlyUnresolved,
        'pageSize': pageSize,
      });
      return [
        for (final e in _rawList(result.data, 'entries'))
          AdminFiscalOperationSummary(
            entryId: e['entryId'] as String,
            operationType: e['operationType'] as String,
            status: e['status'] as String,
            amountMinorUnits: e['amountMinorUnits'] as int,
            currencyCode: e['currencyCode'] as String,
            checkId: e['checkId'] as String?,
            providerId: e['providerId'] as String?,
            createdAt: DateTime.parse(e['createdAt'] as String),
            resolvedAt: e['resolvedAt'] != null
                ? DateTime.parse(e['resolvedAt'] as String)
                : null,
          ),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<AdminOfflineLeaseSummary>> listOfflineLeasesForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('listOfflineLeasesForBranch');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'pageSize': pageSize,
      });
      return [
        for (final l in _rawList(result.data, 'leases'))
          AdminOfflineLeaseSummary(
            leaseId: l['leaseId'] as String,
            deviceId: l['deviceId'] as String,
            issuedToStaffUid: l['issuedToStaffUid'] as String,
            expiresAt: DateTime.parse(l['expiresAt'] as String),
            revoked: l['revoked'] as bool,
            transactionsUsed: l['transactionsUsed'] as int,
            maxTransactionCount: l['maxTransactionCount'] as int,
            createdAt: DateTime.parse(l['createdAt'] as String),
          ),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

/// Fail-closed stand-in when Firebase isn't ready — mirrors
/// `UnavailableTrustedDeviceGateway`'s own established shape
/// (`admin_dependencies_provider.dart`'s gate pattern): every method throws
/// rather than returning empty/fabricated data, so a missing backend
/// connection surfaces as an honest error state, never a silently-empty
/// financial list.
class UnavailableAdminFinancialGateway implements AdminFinancialGateway {
  const UnavailableAdminFinancialGateway();

  Never _unavailable() => throw const AdminFinancialException(
        'unavailable',
        'Finansal veriler şu anda kullanılamıyor.',
      );

  @override
  Future<List<AdminPaymentSessionSummary>> listPaymentSessionsForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  }) async =>
      _unavailable();

  @override
  Future<List<AdminRefundSummary>> listRefundsForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  }) async =>
      _unavailable();

  @override
  Future<List<AdminCashSessionSummary>> listCashSessionsForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  }) async =>
      _unavailable();

  @override
  Future<List<AdminFiscalOperationSummary>> listFiscalOperationsForBranch({
    required String organizationId,
    required String branchId,
    bool onlyUnresolved = false,
    int pageSize = 50,
  }) async =>
      _unavailable();

  @override
  Future<List<AdminOfflineLeaseSummary>> listOfflineLeasesForBranch({
    required String organizationId,
    required String branchId,
    int pageSize = 50,
  }) async =>
      _unavailable();
}
