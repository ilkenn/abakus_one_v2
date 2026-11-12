/// 2026-11-12 (Faz 4, ADR-080) — the "Kurye & Paket Raporu" as the server
/// computed it (`getCourierDeliveryReport`). Read-only: every figure comes
/// from the settlement records ("Kurye Hesap Kapat"), never from the client.
enum CourierKind { internal, pool }

class PaymentMethodTotal {
  const PaymentMethodTotal({
    required this.paymentMethodId,
    required this.displayName,
    required this.reportingCategory,
    required this.count,
    required this.amountMinorUnits,
  });

  final String paymentMethodId;
  final String displayName;

  /// `cash`, `card` or `mealCard`.
  final String reportingCategory;
  final int count;
  final int amountMinorUnits;

  /// "Nakit", "POS (Kredi Kartı)", "Yemek Kartı — Multinet".
  String get label => switch (reportingCategory) {
        'cash' => 'Nakit',
        'card' => 'POS ($displayName)',
        'mealCard' => 'Yemek Kartı — $displayName',
        _ => displayName,
      };
}

class CourierReportAggregate {
  const CourierReportAggregate({
    required this.packageCount,
    required this.collectedMinorUnits,
    required this.averagePreparationMinutes,
    required this.averageDeliveryMinutes,
    required this.cashDifferenceMinorUnits,
    required this.settlementCount,
    required this.paymentMethods,
  });

  final int packageCount;
  final int collectedMinorUnits;
  final double? averagePreparationMinutes;
  final double? averageDeliveryMinutes;

  /// Sum of "Kurye Farkı": negative = couriers brought less than expected.
  final int cashDifferenceMinorUnits;
  final int settlementCount;
  final List<PaymentMethodTotal> paymentMethods;

  static const empty = CourierReportAggregate(
    packageCount: 0,
    collectedMinorUnits: 0,
    averagePreparationMinutes: null,
    averageDeliveryMinutes: null,
    cashDifferenceMinorUnits: 0,
    settlementCount: 0,
    paymentMethods: [],
  );
}

class CourierReportRow {
  const CourierReportRow({
    required this.courierId,
    required this.courierName,
    required this.kind,
    required this.aggregate,
  });

  final String courierId;
  final String courierName;
  final CourierKind kind;
  final CourierReportAggregate aggregate;
}

class PoolOrderReportRow {
  const PoolOrderReportRow({
    required this.orderId,
    required this.orderNumber,
    required this.courierName,
    required this.neighborhoodName,
    required this.amountMinorUnits,
    required this.paymentMethodDisplayName,
    required this.collectedAt,
    required this.deliveryMinutes,
  });

  final String orderId;
  final String orderNumber;
  final String courierName;
  final String neighborhoodName;
  final int amountMinorUnits;
  final String paymentMethodDisplayName;
  final DateTime collectedAt;
  final double? deliveryMinutes;
}

class CourierDeliveryReport {
  const CourierDeliveryReport({
    required this.from,
    required this.to,
    required this.totals,
    required this.internal,
    required this.pool,
    required this.couriers,
    required this.poolOrders,
    required this.truncated,
  });

  final DateTime from;
  final DateTime to;
  final CourierReportAggregate totals;
  final CourierReportAggregate internal;
  final CourierReportAggregate pool;
  final List<CourierReportRow> couriers;
  final List<PoolOrderReportRow> poolOrders;

  /// More than the server's cap of settled packages fell in the range.
  final bool truncated;

  bool get isEmpty => totals.packageCount == 0 && totals.settlementCount == 0;
}
