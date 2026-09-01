/// AP-4 Wave D — read-only summaries for Admin's branch-wide financial
/// destinations. Mirrors the exact projections `adminFinancialView.ts`'s
/// five callables return (`functions/src/adminFinancialView.ts`) — never
/// richer than the wire shape, never locally re-derived.
library;

class AdminPaymentSessionSummary {
  const AdminPaymentSessionSummary({
    required this.sessionId,
    required this.checkId,
    required this.status,
    required this.payableAmountMinorUnits,
    required this.settledAmountMinorUnits,
    required this.currencyCode,
    required this.createdAt,
  });

  final String sessionId;
  final String checkId;
  final String status;
  final int payableAmountMinorUnits;
  final int settledAmountMinorUnits;
  final String currencyCode;
  final DateTime createdAt;
}

class AdminRefundSummary {
  const AdminRefundSummary({
    required this.refundId,
    required this.checkId,
    required this.refundType,
    required this.amountMinorUnits,
    required this.status,
    required this.reasonCode,
    required this.createdAt,
  });

  final String refundId;
  final String checkId;
  final String refundType;
  final int amountMinorUnits;
  final String status;
  final String reasonCode;
  final DateTime createdAt;
}

class AdminCashSessionSummary {
  const AdminCashSessionSummary({
    required this.sessionId,
    required this.drawerId,
    required this.status,
    required this.businessDate,
    required this.openingFloatAmountMinorUnits,
    required this.settledAmountMinorUnits,
    required this.currencyCode,
    required this.createdAt,
  });

  final String sessionId;
  final String drawerId;
  final String status;
  final String businessDate;
  final int openingFloatAmountMinorUnits;
  final int settledAmountMinorUnits;
  final String currencyCode;
  final DateTime createdAt;
}

class AdminFiscalOperationSummary {
  const AdminFiscalOperationSummary({
    required this.entryId,
    required this.operationType,
    required this.status,
    required this.amountMinorUnits,
    required this.currencyCode,
    required this.checkId,
    required this.providerId,
    required this.createdAt,
    required this.resolvedAt,
  });

  final String entryId;
  final String operationType;
  final String status;
  final int amountMinorUnits;
  final String currencyCode;
  final String? checkId;
  final String? providerId;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  /// Mirrors `adminFinancialView.ts`'s own `onlyUnresolved` filter exactly
  /// — `timedOut` is included because no reconciliation sweep yet promotes
  /// it to `unknownReconciliationRequired` (AP-4 Wave D, disclosed gap).
  bool get isUnresolved =>
      status == 'timedOut' ||
      status == 'unknownReconciliationRequired' ||
      status == 'manualInterventionRequired';
}

class AdminOfflineLeaseSummary {
  const AdminOfflineLeaseSummary({
    required this.leaseId,
    required this.deviceId,
    required this.issuedToStaffUid,
    required this.expiresAt,
    required this.revoked,
    required this.transactionsUsed,
    required this.maxTransactionCount,
    required this.createdAt,
  });

  final String leaseId;
  final String deviceId;
  final String issuedToStaffUid;
  final DateTime expiresAt;
  final bool revoked;
  final int transactionsUsed;
  final int maxTransactionCount;
  final DateTime createdAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
