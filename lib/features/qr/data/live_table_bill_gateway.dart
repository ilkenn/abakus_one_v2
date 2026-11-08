import 'package:cloud_functions/cloud_functions.dart' as functions;

/// Adım 5 (2026-11-07) — "Canlı Adisyon Okuma Gateway'i" (ADR-058's
/// deferred item). Mirrors [TableGuestSessionGateway]'s own
/// call/exception shape exactly.
class LiveTableBillLineSummary {
  const LiveTableBillLineSummary({
    required this.productName,
    required this.quantity,
    required this.unitPriceMinorUnits,
  });

  final String productName;
  final int quantity;
  final int unitPriceMinorUnits;

  factory LiveTableBillLineSummary.fromWire(Map<String, dynamic> data) {
    return LiveTableBillLineSummary(
      productName: data['productName'] as String? ?? '',
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      unitPriceMinorUnits: (data['unitPriceMinorUnits'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The table's current, running open bill — narrow, read-only slice
/// returned by the `getLiveTableBill` Cloud Function. See that function's
/// own doc comment for exactly what [runningTotalMinorUnits] does and does
/// not account for (notably: not yet net of any partial payment already
/// made against a split check).
class LiveTableBill {
  const LiveTableBill({
    required this.currencyCode,
    required this.subtotalMinorUnits,
    required this.appliedDiscountsMinorUnits,
    required this.runningTotalMinorUnits,
    required this.lines,
  });

  final String currencyCode;
  final int subtotalMinorUnits;
  final int appliedDiscountsMinorUnits;
  final int runningTotalMinorUnits;
  final List<LiveTableBillLineSummary> lines;

  factory LiveTableBill.fromWire(Map<String, dynamic> data) {
    return LiveTableBill(
      currencyCode: data['currencyCode'] as String? ?? 'TRY',
      subtotalMinorUnits: (data['subtotalMinorUnits'] as num?)?.toInt() ?? 0,
      appliedDiscountsMinorUnits:
          (data['appliedDiscountsMinorUnits'] as num?)?.toInt() ?? 0,
      runningTotalMinorUnits:
          (data['runningTotalMinorUnits'] as num?)?.toInt() ?? 0,
      lines: [
        for (final raw in (data['lines'] as List? ?? const []))
          LiveTableBillLineSummary.fromWire(
              Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }
}

class LiveTableBillException implements Exception {
  const LiveTableBillException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'LiveTableBillException($code): $message';
}

abstract interface class LiveTableBillGateway {
  /// [tableSessionId] is [ActiveTableContext.session]'s own `id` — the
  /// real `tableGuestSessions` document id (see that class's own doc
  /// comment for why, confusingly, this is held on the `session` field and
  /// not the `guestSession` field).
  Future<LiveTableBill> getLiveTableBill({required String tableSessionId});
}

class FirebaseLiveTableBillGateway implements LiveTableBillGateway {
  const FirebaseLiveTableBillGateway();

  @override
  Future<LiveTableBill> getLiveTableBill(
      {required String tableSessionId}) async {
    final callable =
        functions.FirebaseFunctions.instance.httpsCallable('getLiveTableBill');
    try {
      final result = await callable
          .call<Map<String, dynamic>>({'tableSessionId': tableSessionId});
      return LiveTableBill.fromWire(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      throw LiveTableBillException(
        error.code,
        error.message ?? 'Masa hesabı okunamadı.',
      );
    }
  }
}
