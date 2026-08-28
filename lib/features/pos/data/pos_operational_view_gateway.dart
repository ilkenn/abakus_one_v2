import 'package:cloud_functions/cloud_functions.dart' as functions;

/// The real, device-gated read boundary onto `functions/src
/// /posOperationalView.ts` — AP-3 continuation (`docs/decisions.md`
/// ADR-041's own "no longer blocked" follow-up). Every method requires the
/// caller to already hold a real trusted-device session
/// (`organizationId`/`branchId`/`deviceId`/`deviceSessionId` — sourced from
/// `TrustedDeviceSessionController.ensureFreshSession()`, never invented
/// client-side) — the server independently re-verifies all of it
/// (`requireActiveDeviceSession`) regardless of what this gateway sends.

class PosBranchTableSummary {
  const PosBranchTableSummary({
    required this.tableId,
    required this.displayName,
    required this.status,
    required this.activeTableSessionId,
    required this.pendingQrLineCount,
  });

  final String tableId;
  final String displayName;
  final String status;
  final String? activeTableSessionId;
  final int pendingQrLineCount;

  factory PosBranchTableSummary.fromWire(Map<String, dynamic> data) {
    return PosBranchTableSummary(
      tableId: data['tableId'] as String,
      displayName: data['displayName'] as String,
      status: data['status'] as String,
      activeTableSessionId: data['activeTableSessionId'] as String?,
      pendingQrLineCount: data['pendingQrLineCount'] as int,
    );
  }
}

class PosBranchOverviewPage {
  const PosBranchOverviewPage({
    required this.tables,
    required this.nextCursor,
    required this.version,
    required this.unchanged,
  });

  final List<PosBranchTableSummary> tables;
  final String? nextCursor;
  final String version;

  /// `true` when [PosOperationalViewGateway.getBranchOverview]'s
  /// `ifNoneMatchVersion` matched the server's current version — [tables]
  /// is empty and stale in that case; the caller must keep its
  /// previously-rendered list rather than replacing it with this page.
  final bool unchanged;
}

class PosOrderLineSummary {
  const PosOrderLineSummary({
    required this.productName,
    required this.quantity,
    required this.unitPriceMinorUnits,
    required this.status,
    required this.subAccountId,
  });

  final String productName;
  final int quantity;
  final int unitPriceMinorUnits;
  final String status;
  final String? subAccountId;

  factory PosOrderLineSummary.fromWire(
      Map<String, dynamic> data, int lineIndex) {
    final unitPrice = data['unitPrice'];
    return PosOrderLineSummary(
      productName: data['productName'] as String,
      quantity: data['quantity'] as int,
      unitPriceMinorUnits:
          unitPrice is Map ? (unitPrice['minorUnits'] as int? ?? 0) : 0,
      status: data['status'] as String? ?? 'accepted',
      subAccountId: data['subAccountId'] as String?,
    );
  }
}

class PosTableOrderSummary {
  const PosTableOrderSummary({
    required this.orderId,
    required this.subAccountId,
    required this.mode,
    required this.linesDispositionSummary,
    required this.lines,
  });

  final String orderId;
  final String? subAccountId;
  final String mode;
  final String? linesDispositionSummary;
  final List<PosOrderLineSummary> lines;

  factory PosTableOrderSummary.fromWire(Map<String, dynamic> data) {
    final rawLines = (data['lines'] as List? ?? const []);
    return PosTableOrderSummary(
      orderId: data['id'] as String,
      subAccountId: data['subAccountId'] as String?,
      mode: data['mode'] as String? ?? 'guestSession',
      linesDispositionSummary: data['linesDispositionSummary'] as String?,
      lines: [
        for (var i = 0; i < rawLines.length; i++)
          PosOrderLineSummary.fromWire(
              Map<String, dynamic>.from(rawLines[i] as Map), i),
      ],
    );
  }
}

/// One active split allocation on the open check — mirrors `functions/src
/// /checkAllocationConfig.ts`'s `CheckAllocationDoc`. Carries the allocation
/// id required for a `scope: "product"` financial-adjustment request
/// (`checkFinancialAdjustments.ts`'s `requestCheckFinancialAdjustment`).
class PosCheckAllocationSummary {
  const PosCheckAllocationSummary({
    required this.id,
    required this.subAccountId,
    required this.status,
    required this.allocatedAmountMinorUnits,
  });

  final String id;
  final String subAccountId;
  final String status;
  final int allocatedAmountMinorUnits;

  factory PosCheckAllocationSummary.fromWire(Map<String, dynamic> data) {
    return PosCheckAllocationSummary(
      id: data['id'] as String,
      subAccountId: data['subAccountId'] as String,
      status: data['status'] as String,
      allocatedAmountMinorUnits: data['allocatedAmountMinorUnits'] as int? ?? 0,
    );
  }
}

class PosTableOperationalView {
  const PosTableOperationalView({
    required this.tableId,
    required this.status,
    required this.tableSessionId,
    required this.subAccounts,
    required this.checks,
    required this.orders,
    this.allocations = const [],
  });

  final String tableId;
  final String status;
  final String? tableSessionId;
  final List<Map<String, dynamic>> subAccounts;
  final List<Map<String, dynamic>> checks;
  final List<PosTableOrderSummary> orders;
  final List<PosCheckAllocationSummary> allocations;

  bool get hasActiveSession => tableSessionId != null;

  factory PosTableOperationalView.fromWire(Map<String, dynamic> data) {
    final tableSession = data['tableSession'];
    final rawOrders = (data['orders'] as List? ?? const []);
    return PosTableOperationalView(
      tableId: data['tableId'] as String,
      status: data['status'] as String,
      tableSessionId:
          tableSession is Map ? tableSession['id'] as String? : null,
      subAccounts: [
        for (final raw in (data['subAccounts'] as List? ?? const []))
          Map<String, dynamic>.from(raw as Map),
      ],
      checks: [
        for (final raw in (data['checks'] as List? ?? const []))
          Map<String, dynamic>.from(raw as Map),
      ],
      orders: [
        for (final raw in rawOrders)
          PosTableOrderSummary.fromWire(Map<String, dynamic>.from(raw as Map)),
      ],
      allocations: [
        for (final raw in (data['allocations'] as List? ?? const []))
          PosCheckAllocationSummary.fromWire(
              Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }
}

class PosOperationalViewException implements Exception {
  const PosOperationalViewException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'PosOperationalViewException($code): $message';
}

abstract interface class PosOperationalViewGateway {
  Future<PosBranchOverviewPage> getBranchOverview({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    String? cursor,
    String? ifNoneMatchVersion,
  });

  Future<PosTableOperationalView> getTableView({
    required String organizationId,
    required String branchId,
    required String tableId,
    required String deviceId,
    required String deviceSessionId,
  });
}

class FirebasePosOperationalViewGateway implements PosOperationalViewGateway {
  const FirebasePosOperationalViewGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw PosOperationalViewException(
      error.code,
      error.message ?? 'İşlem gerçekleştirilemedi.',
    );
  }

  @override
  Future<PosBranchOverviewPage> getBranchOverview({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    String? cursor,
    String? ifNoneMatchVersion,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'getPosBranchTableOverview',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'deviceId': deviceId,
        'deviceSessionId': deviceSessionId,
        if (cursor != null) 'cursor': cursor,
        if (ifNoneMatchVersion != null)
          'ifNoneMatchVersion': ifNoneMatchVersion,
      });
      final data = result.data;
      final unchanged = data['unchanged'] as bool;
      return PosBranchOverviewPage(
        tables: unchanged
            ? const []
            : [
                for (final raw in (data['tables'] as List))
                  PosBranchTableSummary.fromWire(
                      Map<String, dynamic>.from(raw as Map)),
              ],
        nextCursor: data['nextCursor'] as String?,
        version: data['version'] as String,
        unchanged: unchanged,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<PosTableOperationalView> getTableView({
    required String organizationId,
    required String branchId,
    required String tableId,
    required String deviceId,
    required String deviceSessionId,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'getPosTableOperationalView',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'tableId': tableId,
        'deviceId': deviceId,
        'deviceSessionId': deviceSessionId,
      });
      return PosTableOperationalView.fromWire(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

class UnavailablePosOperationalViewGateway
    implements PosOperationalViewGateway {
  const UnavailablePosOperationalViewGateway();

  Never _unavailable() => throw const PosOperationalViewException(
        'unavailable',
        'POS veri servisi şu anda kullanılamıyor.',
      );

  @override
  Future<PosBranchOverviewPage> getBranchOverview({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    String? cursor,
    String? ifNoneMatchVersion,
  }) async =>
      _unavailable();

  @override
  Future<PosTableOperationalView> getTableView({
    required String organizationId,
    required String branchId,
    required String tableId,
    required String deviceId,
    required String deviceSessionId,
  }) async =>
      _unavailable();
}
