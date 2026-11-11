import '../../orders/domain/order_line_quantity_label.dart';
import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';

/// The real, device-gated read boundary onto `functions/src
/// /posOperationalView.ts` — AP-3 continuation (`docs/decisions.md`
/// ADR-041's own "no longer blocked" follow-up). Every method requires the
/// caller to already hold a real trusted-device session
/// (`organizationId`/`branchId`/`deviceId`/`deviceSessionId` — sourced from
/// `TrustedDeviceSessionController.ensureFreshSession()`, never invented
/// client-side) — the server independently re-verifies all of it
/// (`requireActiveDeviceSession`) regardless of what this gateway sends.

/// One pending waiter-call/bill-request/etc. ping on a table — Dine-in
/// Sprint 3, types extended Self-Order QR Faz 5. [type] is kept as a raw
/// `String` (mirrors this file's own `PosTableOperationalView.status`
/// precedent) — `'callWaiter'`/`'requestBill'`/`'ashtrayOrService'`/
/// `'clearTable'`/`'customNote'`, forward-compatible with an unrecognized
/// future value. [note] is only ever non-null for `'customNote'`.
class PosPendingServiceRequest {
  const PosPendingServiceRequest({
    required this.requestId,
    required this.type,
    this.note,
  });

  final String requestId;
  final String type;
  final String? note;

  factory PosPendingServiceRequest.fromWire(Map<String, dynamic> data) {
    return PosPendingServiceRequest(
      requestId: data['requestId'] as String,
      type: data['type'] as String,
      note: data['note'] as String?,
    );
  }
}

/// One entry in "Çok Tercih Edilenler" (Top 20 best-sellers), 2026-11-03 —
/// `functions/src/posTopSellingProducts.ts` (BR-POS-001). [quantitySold] is
/// the real sum of `accepted`-line quantity across this branch's orders in
/// the server's lookback window — never a client-side guess.
class PosTopSellingProduct {
  const PosTopSellingProduct({
    required this.productId,
    required this.productName,
    required this.quantitySold,
  });

  final String productId;
  final String productName;
  final int quantitySold;

  factory PosTopSellingProduct.fromWire(Map<String, dynamic> data) {
    return PosTopSellingProduct(
      productId: data['productId'] as String,
      productName: data['productName'] as String,
      quantitySold: (data['quantitySold'] as num).toInt(),
    );
  }
}

class PosBranchTableSummary {
  const PosBranchTableSummary({
    required this.tableId,
    required this.displayName,
    required this.status,
    required this.activeTableSessionId,
    required this.pendingQrLineCount,
    this.kitchenReadyOrderCount = 0,
    this.pendingServiceRequests = const [],
    this.areaName = '',
    this.activePortionCount = 0,
    this.capacity,
  });

  final String tableId;
  final String displayName;
  final String status;
  final String? activeTableSessionId;
  final int pendingQrLineCount;

  /// Adım 5 (2026-11-07) — how many of this table's orders have already
  /// reached `status == "ready"` (every kitchen line confirmed ready) but
  /// haven't moved past that yet — the Masalar grid card's "Mutfakta Hazır"
  /// badge.
  final int kitchenReadyOrderCount;
  final List<PosPendingServiceRequest> pendingServiceRequests;

  /// `RestaurantTable.areaName` (free text, e.g. "Bahçe"/"Salon"/"Teras"),
  /// passed straight through — the Masalar grid's own area-filter tabs
  /// (2026-11-06). Empty when the table has none set.
  final String areaName;

  /// 2026-11-11 — main portions ordered at this table right now (server:
  /// `countActivePortions` — live orders/lines only, beverages excluded).
  /// Drives the bird's-eye card: one filled chair per portion, capped to
  /// the chairs drawn. 0 = no live order.
  final int activePortionCount;

  /// `RestaurantTable.capacity`, `null` when unset.
  final int? capacity;

  factory PosBranchTableSummary.fromWire(Map<String, dynamic> data) {
    return PosBranchTableSummary(
      tableId: data['tableId'] as String,
      displayName: data['displayName'] as String,
      areaName: data['areaName'] as String? ?? '',
      status: data['status'] as String,
      activeTableSessionId: data['activeTableSessionId'] as String?,
      pendingQrLineCount: data['pendingQrLineCount'] as int,
      kitchenReadyOrderCount: data['kitchenReadyOrderCount'] as int? ?? 0,
      activePortionCount: data['activePortionCount'] as int? ?? 0,
      capacity: data['capacity'] as int?,
      pendingServiceRequests: [
        for (final raw in (data['pendingServiceRequests'] as List? ?? const []))
          PosPendingServiceRequest.fromWire(
              Map<String, dynamic>.from(raw as Map)),
      ],
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

class PosOrderLineModifierSummary {
  const PosOrderLineModifierSummary({
    required this.groupName,
    required this.optionName,
    required this.quantity,
    required this.unitExtraPriceMinorUnits,
  });

  final String groupName;
  final String optionName;
  final int quantity;
  final int unitExtraPriceMinorUnits;

  factory PosOrderLineModifierSummary.fromWire(Map<String, dynamic> data) {
    final unitExtraPrice = data['unitExtraPrice'];
    return PosOrderLineModifierSummary(
      groupName: data['groupName'] as String? ?? '',
      optionName: data['optionName'] as String? ?? '',
      quantity: data['quantity'] as int? ?? 1,
      unitExtraPriceMinorUnits: unitExtraPrice is Map
          ? (unitExtraPrice['minorUnits'] as int? ?? 0)
          : 0,
    );
  }
}

class PosOrderLineSummary {
  const PosOrderLineSummary({
    this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceMinorUnits,
    required this.status,
    required this.subAccountId,
    this.modifiers = const [],
    this.excludedIngredients = const [],
    this.kitchenNote = '',
    this.weightGrams,
  });

  final String? productId;
  final String productName;
  final int quantity;
  final int unitPriceMinorUnits;
  final String status;
  final String? subAccountId;

  /// Mirrors `KitchenTicketMapper`'s inputs — the till receipt (2026-11-05)
  /// prints the same selection detail the kitchen ticket already does, so
  /// kitchen staff and the printed adisyon never disagree on what was
  /// actually ordered.
  final List<PosOrderLineModifierSummary> modifiers;
  final List<String> excludedIngredients;
  final String kitchenNote;

  /// ADR-067 (2026-11-09) — whole grams for a sold-by-weight line
  /// ([quantity] is then 1, [unitPriceMinorUnits] that weight's price);
  /// `null` for every per-piece line.
  final int? weightGrams;

  /// Paid add-ons per unit: Σ (modifier unit extra price × modifier
  /// quantity). [unitPriceMinorUnits] is the product's base price only.
  int get modifiersExtraMinorUnits => modifiers.fold(
        0,
        (sum, m) => sum + m.unitExtraPriceMinorUnits * m.quantity,
      );

  /// Per-unit price including paid modifiers.
  int get unitTotalMinorUnits => unitPriceMinorUnits + modifiersExtraMinorUnits;

  /// 2026-11-10 — the line's full value, the same formula as the server's
  /// `computeLineValueMinorUnits` (checkAllocationConfig.ts): (base +
  /// modifiers) × quantity. Every POS total/line amount must use this, never
  /// `unitPriceMinorUnits × quantity`, or paid extras silently disappear
  /// from the screen while the server's check still charges them.
  int get lineTotalMinorUnits => unitTotalMinorUnits * quantity;

  /// "2x" / "350 g" — see `orderLineQuantityLabel`.
  String get quantityLabel =>
      orderLineQuantityLabel(quantity: quantity, weightGrams: weightGrams);

  factory PosOrderLineSummary.fromWire(
      Map<String, dynamic> data, int lineIndex) {
    final unitPrice = data['unitPrice'];
    return PosOrderLineSummary(
      productId: data['productId'] as String?,
      productName: data['productName'] as String,
      quantity: data['quantity'] as int,
      unitPriceMinorUnits:
          unitPrice is Map ? (unitPrice['minorUnits'] as int? ?? 0) : 0,
      status: data['status'] as String? ?? 'accepted',
      subAccountId: data['subAccountId'] as String?,
      modifiers: [
        for (final raw in (data['modifiers'] as List? ?? const []))
          PosOrderLineModifierSummary.fromWire(
              Map<String, dynamic>.from(raw as Map)),
      ],
      excludedIngredients: [
        for (final raw in (data['excludedIngredients'] as List? ?? const []))
          raw as String,
      ],
      kitchenNote: data['kitchenNote'] as String? ?? '',
      weightGrams: (data['weightGrams'] as num?)?.toInt(),
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

/// Prefers `readyForPayment` (staff already asked for the bill) over
/// `open`, then falls back to the first `open` check — `paid`/`cancelled`
/// checks are never a valid target. Shared by `PrintTableReceipt` and the
/// Masalar grid's "Ödeme Al" quick action (2026-11-06) — both need the
/// exact same "which check does this table's own quick action apply to"
/// resolution.
String? resolveOpenOrReadyForPaymentCheckId(PosTableOperationalView view) {
  final readyForPayment = view.checks
      .where((c) => c['status'] == 'readyForPayment')
      .map((c) => c['id'] as String?)
      .whereType<String>();
  if (readyForPayment.isNotEmpty) return readyForPayment.first;

  final open = view.checks
      .where((c) => c['status'] == 'open')
      .map((c) => c['id'] as String?)
      .whereType<String>();
  return open.isNotEmpty ? open.first : null;
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

  Future<List<PosTopSellingProduct>> getTopSellingProducts({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
  });
}

class FirebasePosOperationalViewGateway implements PosOperationalViewGateway {
  FirebasePosOperationalViewGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw PosOperationalViewException(
      error.code,
      error.message ?? 'İşlem gerçekleştirilemedi.',
    );
  }

  /// The official `cloud_functions` plugin ships no native Windows desktop
  /// implementation at all (confirmed absent from `windows/flutter/
  /// generated_plugin_registrant.cc`) — every `httpsCallable(...).call()`
  /// on Windows throws `[firebase_functions/unknown] Unable to establish
  /// connection on channel...`. Unlike this session's earlier Windows
  /// fixes (skip the call, fall back to a safe default), these two
  /// callables have no such fallback — there is no non-callable source
  /// for real table data — so on Windows, this routes through
  /// [RestCallableClient] instead: the same real backend, reached via
  /// plain HTTP(S) rather than the broken native plugin (PC Yönetici
  /// İnceleme Modu, 2026-09-20). Every other platform takes the exact same
  /// `cloud_functions` path as before — byte-for-byte unchanged.
  ///
  /// **2026-10-29 fix**: this previously also required
  /// `FirebaseFunctionsEmulatorConfig.shouldUseEmulator(AppEnvironment
  /// .current)` — this doc comment's own prior claim that "Windows against
  /// a real deployed project takes the exact same `cloud_functions` path"
  /// was the actual bug, not a safe fallback: that path is unconditionally
  /// broken on Windows regardless of environment. See
  /// `StaffClaimsSyncClient.syncAndRefresh`'s identical fix.
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final useRest = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw PosOperationalViewException(error.code, error.message);
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
  Future<PosBranchOverviewPage> getBranchOverview({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    String? cursor,
    String? ifNoneMatchVersion,
  }) async {
    final data = await _call('getPosBranchTableOverview', {
      'organizationId': organizationId,
      'branchId': branchId,
      'deviceId': deviceId,
      'deviceSessionId': deviceSessionId,
      if (cursor != null) 'cursor': cursor,
      if (ifNoneMatchVersion != null) 'ifNoneMatchVersion': ifNoneMatchVersion,
    });
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
  }

  @override
  Future<PosTableOperationalView> getTableView({
    required String organizationId,
    required String branchId,
    required String tableId,
    required String deviceId,
    required String deviceSessionId,
  }) async {
    final data = await _call('getPosTableOperationalView', {
      'organizationId': organizationId,
      'branchId': branchId,
      'tableId': tableId,
      'deviceId': deviceId,
      'deviceSessionId': deviceSessionId,
    });
    return PosTableOperationalView.fromWire(data);
  }

  @override
  Future<List<PosTopSellingProduct>> getTopSellingProducts({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
  }) async {
    final data = await _call('getTopSellingProducts', {
      'organizationId': organizationId,
      'branchId': branchId,
      'deviceId': deviceId,
      'deviceSessionId': deviceSessionId,
    });
    return [
      for (final raw in (data['products'] as List))
        PosTopSellingProduct.fromWire(Map<String, dynamic>.from(raw as Map)),
    ];
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

  @override
  Future<List<PosTopSellingProduct>> getTopSellingProducts({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
  }) async =>
      _unavailable();
}
