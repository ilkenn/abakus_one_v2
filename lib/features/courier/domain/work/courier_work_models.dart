import 'courier_contact_plan.dart';

/// 2026-11-12 (Faz 3b) — the courier app's server-backed read models
/// (`functions/src/courierPool.ts`). Plain value types; timestamps arrive
/// either as Firestore `Timestamp`s (anything with `toDate()`) or ISO
/// strings.
DateTime? _date(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  try {
    return (raw as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

/// The pay-on-delivery methods a courier can report at "Teslim Ettim"
/// (the server's `STAFF_DELIVERY_PAYMENT_METHOD_IDS`).
const courierDeliveryPaymentMethods = [
  (id: 'cash', label: 'Nakit'),
  (id: 'credit_card', label: 'POS'),
  (id: 'pluxee', label: 'Pluxee'),
  (id: 'multinet', label: 'Multinet'),
  (id: 'setcard', label: 'Setcard'),
  (id: 'edenred', label: 'Edenred'),
];

String courierPaymentMethodLabel(String? id) =>
    courierDeliveryPaymentMethods.where((m) => m.id == id).firstOrNull?.label ??
    (id ?? '-');

/// `courierAccounts/{uid}` — who the signed-in account is as a courier.
class CourierWorkAccount {
  const CourierWorkAccount({
    required this.uid,
    required this.organizationId,
    required this.courierId,
    required this.displayName,
    required this.isExternal,
    required this.serviceDistrictIds,
    required this.isActive,
  });

  final String uid;
  final String organizationId;
  final String courierId;
  final String displayName;

  /// A `pool` (external) courier — the only kind that sees the pool.
  final bool isExternal;
  final List<String> serviceDistrictIds;
  final bool isActive;

  factory CourierWorkAccount.fromFirestore(
          String uid, Map<String, dynamic> data) =>
      CourierWorkAccount(
        uid: uid,
        organizationId: data['organizationId'] as String? ?? '',
        courierId: data['courierId'] as String? ?? '',
        displayName: data['displayName'] as String? ?? '',
        isExternal: data['type'] == 'pool',
        serviceDistrictIds: [
          for (final d in (data['serviceDistrictIds'] as List?) ?? const [])
            if (d is String) d,
        ],
        isActive: (data['status'] as String? ?? 'active') == 'active',
      );
}

enum CourierWorkOrderStatus {
  reserved,
  assigned,
  departed,
  deliveredAwaitingSettlement;

  static CourierWorkOrderStatus parse(String? raw) => switch (raw) {
        'reserved' => reserved,
        'departed' => departed,
        'deliveredAwaitingSettlement' => deliveredAwaitingSettlement,
        _ => assigned,
      };
}

/// `courierAssignedOrders/{orderId}` — one order the courier carries.
class CourierWorkOrder {
  const CourierWorkOrder({
    required this.orderId,
    required this.orderNumber,
    required this.branchName,
    required this.customerName,
    required this.customerPhone,
    required this.neighborhoodName,
    required this.addressLine,
    required this.courierNote,
    required this.amountDueMinorUnits,
    required this.plannedPaymentMethodId,
    required this.reportedPaymentMethodId,
    required this.status,
    this.destinationLatitude,
    this.destinationLongitude,
    this.source = CourierOrderSource.own,
    this.marketplaceOrderCode,
    this.switchboardPhone,
  });

  final String orderId;
  final String orderNumber;
  final String branchName;
  final String customerName;

  /// `null` once delivered (KVKK) — the server removes it, together with
  /// [customerName], [addressLine] and [courierNote] (ADR-085 stage 2).
  final String? customerPhone;
  final String neighborhoodName;
  final String addressLine;
  final String courierNote;
  final int amountDueMinorUnits;
  final String? plannedPaymentMethodId;
  final String? reportedPaymentMethodId;
  final CourierWorkOrderStatus status;

  /// ADR-085 stage 4 — the address pin, when the address has one; removed
  /// at delivery with the rest of the personal data.
  final double? destinationLatitude;
  final double? destinationLongitude;

  /// Where the order came from — decides whom "Ara" calls.
  final CourierOrderSource source;

  /// Trendyol/Getir: the order code keyed after the switchboard answers.
  final String? marketplaceOrderCode;

  /// Trendyol/Getir: the restaurant line to call (organization setting).
  final String? switchboardPhone;

  /// Open work first: on the road, assigned, reserved, then delivered.
  int get statusRank => switch (status) {
        CourierWorkOrderStatus.departed => 0,
        CourierWorkOrderStatus.assigned => 1,
        CourierWorkOrderStatus.reserved => 2,
        CourierWorkOrderStatus.deliveredAwaitingSettlement => 3,
      };

  factory CourierWorkOrder.fromFirestore(
          String id, Map<String, dynamic> data) =>
      CourierWorkOrder(
        orderId: data['orderId'] as String? ?? id,
        orderNumber: data['orderNumber'] as String? ?? id,
        branchName: data['branchName'] as String? ?? '',
        customerName: data['customerName'] as String? ?? '',
        customerPhone: data['customerPhone'] as String?,
        neighborhoodName: data['neighborhoodName'] as String? ?? '',
        addressLine: data['addressLine'] as String? ?? '',
        courierNote: data['courierNote'] as String? ?? '',
        amountDueMinorUnits: _int(data['amountDueMinorUnits']),
        plannedPaymentMethodId: data['plannedPaymentMethodId'] as String?,
        reportedPaymentMethodId: data['reportedPaymentMethodId'] as String?,
        status: CourierWorkOrderStatus.parse(data['status'] as String?),
        destinationLatitude: (data['destinationLatitude'] as num?)?.toDouble(),
        destinationLongitude:
            (data['destinationLongitude'] as num?)?.toDouble(),
        source:
            CourierOrderSource.parse(data['marketplaceProvider'] as String?),
        marketplaceOrderCode: data['marketplaceOrderCode'] as String?,
        switchboardPhone: data['switchboardPhone'] as String?,
      );
}

/// `deliveryPoolListings/{orderId}` — an open package in the pool. Never
/// carries the customer's phone or name.
class CourierPoolPackage {
  const CourierPoolPackage({
    required this.orderId,
    required this.orderNumber,
    required this.branchName,
    required this.neighborhoodName,
    required this.addressLine,
    required this.amountDueMinorUnits,
    required this.plannedPaymentMethodId,
    this.publishedAt,
  });

  final String orderId;
  final String orderNumber;
  final String branchName;
  final String neighborhoodName;
  final String addressLine;
  final int amountDueMinorUnits;
  final String? plannedPaymentMethodId;
  final DateTime? publishedAt;

  factory CourierPoolPackage.fromFirestore(
          String id, Map<String, dynamic> data) =>
      CourierPoolPackage(
        orderId: data['orderId'] as String? ?? id,
        orderNumber: data['orderNumber'] as String? ?? id,
        branchName: data['branchName'] as String? ?? '',
        neighborhoodName: data['neighborhoodName'] as String? ?? '',
        addressLine: data['addressLine'] as String? ?? '',
        amountDueMinorUnits: _int(data['amountDueMinorUnits']),
        plannedPaymentMethodId: data['plannedPaymentMethodId'] as String?,
        publishedAt: _date(data['publishedAt']),
      );
}

enum CourierOwnRequestStatus { pending, approved, rejected }

/// `courierPoolRequests/{orderId}_{courierId}` — the courier's own request.
class CourierOwnPoolRequest {
  const CourierOwnPoolRequest({
    required this.requestId,
    required this.orderId,
    required this.orderNumber,
    required this.neighborhoodName,
    required this.amountDueMinorUnits,
    required this.status,
    this.rejection,
    this.createdAt,
  });

  final String requestId;
  final String orderId;
  final String orderNumber;
  final String neighborhoodName;
  final int amountDueMinorUnits;
  final CourierOwnRequestStatus status;

  /// `rejected` / `otherApproved` / `withdrawn` / `orderClosed`.
  final String? rejection;
  final DateTime? createdAt;

  String get statusLabel => switch (status) {
        CourierOwnRequestStatus.pending => 'Onay bekliyor',
        CourierOwnRequestStatus.approved => 'Onaylandı',
        CourierOwnRequestStatus.rejected => switch (rejection) {
            'otherApproved' => 'Başka kuryeye verildi',
            'withdrawn' => 'Havuzdan geri alındı',
            'orderClosed' => 'Sipariş kapandı',
            _ => 'Reddedildi',
          },
      };

  factory CourierOwnPoolRequest.fromFirestore(
          String id, Map<String, dynamic> data) =>
      CourierOwnPoolRequest(
        requestId: id,
        orderId: data['orderId'] as String? ?? '',
        orderNumber: data['orderNumber'] as String? ?? '',
        neighborhoodName: data['neighborhoodName'] as String? ?? '',
        amountDueMinorUnits: _int(data['amountDueMinorUnits']),
        status: switch (data['status']) {
          'approved' => CourierOwnRequestStatus.approved,
          'rejected' => CourierOwnRequestStatus.rejected,
          _ => CourierOwnRequestStatus.pending,
        },
        rejection: data['rejection'] as String?,
        createdAt: _date(data['createdAt']),
      );
}

String formatCourierAmount(int minorUnits) {
  final whole = minorUnits ~/ 100;
  final cents = minorUnits % 100;
  return cents == 0
      ? '$whole TL'
      : '$whole,${cents.toString().padLeft(2, '0')} TL';
}
