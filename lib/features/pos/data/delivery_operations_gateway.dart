import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';
import '../domain/delivery/courier_delivery_report.dart';
import '../domain/delivery/delivery_zone.dart';

/// 2026-11-12 (Faz 4) — the branch's neighborhood delivery rules
/// (`listBranchDeliveryZones` / `upsertBranchDeliveryZone`, ADR-081) and the
/// "Kurye & Paket Raporu" (`getCourierDeliveryReport`, ADR-080). REST on
/// Windows, like every POS gateway.
abstract interface class DeliveryOperationsGateway {
  Future<BranchDeliveryZones> listZones({
    required String organizationId,
    required String branchId,
  });

  /// Manager and above. [districtName] empty → the branch's default district.
  Future<DeliveryZone> upsertZone({
    required String organizationId,
    required String branchId,
    required String neighborhoodName,
    String districtName = '',
    required int minimumOrderMinorUnits,
    int? estimatedDeliveryMinutes,
    bool enabled = true,
  });

  /// Manager and above; `[from, to)`.
  Future<CourierDeliveryReport> courierReport({
    required String organizationId,
    required String branchId,
    required DateTime from,
    required DateTime to,
  });
}

class DeliveryOperationsException implements Exception {
  const DeliveryOperationsException(this.code, this.message, {this.detailCode});
  final String code;
  final String message;

  /// `details.code`, e.g. `deliveryZone/covered-by-other-branch`.
  final String? detailCode;

  bool get isPermissionDenied =>
      code == 'permission-denied' || code == 'permission_denied';

  @override
  String toString() => 'DeliveryOperationsException($code): $message';
}

DeliveryZone deliveryZoneFromWire(Map<String, dynamic> data) => DeliveryZone(
      id: data['id'] as String? ?? '',
      districtId: data['districtId'] as String? ?? '',
      neighborhoodId: data['neighborhoodId'] as String? ?? '',
      neighborhoodName: data['neighborhoodName'] as String? ?? '',
      minimumOrderMinorUnits:
          (data['minimumOrderMinorUnits'] as num?)?.toInt() ?? 0,
      estimatedDeliveryMinutes:
          (data['estimatedDeliveryMinutes'] as num?)?.toInt(),
      enabled: data['enabled'] == true,
    );

BranchDeliveryZones branchDeliveryZonesFromWire(Map<String, dynamic> data) =>
    BranchDeliveryZones(
      defaultDeliveryDistrictId: data['defaultDeliveryDistrictId'] as String?,
      zones: [
        for (final raw in (data['zones'] as List?) ?? const [])
          deliveryZoneFromWire(Map<String, dynamic>.from(raw as Map)),
      ],
    );

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};

CourierReportAggregate _aggregateFromWire(Map<String, dynamic> data) =>
    CourierReportAggregate(
      packageCount: (data['packageCount'] as num?)?.toInt() ?? 0,
      collectedMinorUnits: (data['collectedMinorUnits'] as num?)?.toInt() ?? 0,
      averagePreparationMinutes:
          (data['averagePreparationMinutes'] as num?)?.toDouble(),
      averageDeliveryMinutes:
          (data['averageDeliveryMinutes'] as num?)?.toDouble(),
      cashDifferenceMinorUnits:
          (data['cashDifferenceMinorUnits'] as num?)?.toInt() ?? 0,
      settlementCount: (data['settlementCount'] as num?)?.toInt() ?? 0,
      paymentMethods: [
        for (final raw in (data['paymentMethods'] as List?) ?? const [])
          PaymentMethodTotal(
            paymentMethodId: _map(raw)['paymentMethodId'] as String? ?? '',
            displayName: _map(raw)['displayName'] as String? ?? '',
            reportingCategory: _map(raw)['reportingCategory'] as String? ?? '',
            count: (_map(raw)['count'] as num?)?.toInt() ?? 0,
            amountMinorUnits:
                (_map(raw)['amountMinorUnits'] as num?)?.toInt() ?? 0,
          ),
      ],
    );

CourierDeliveryReport courierDeliveryReportFromWire(Map<String, dynamic> data) {
  final byKind = _map(data['byKind']);
  return CourierDeliveryReport(
    from: DateTime.parse(data['fromIso'] as String),
    to: DateTime.parse(data['toIso'] as String),
    totals: _aggregateFromWire(_map(data['totals'])),
    internal: _aggregateFromWire(_map(byKind['internal'])),
    pool: _aggregateFromWire(_map(byKind['pool'])),
    couriers: [
      for (final raw in (data['couriers'] as List?) ?? const [])
        CourierReportRow(
          courierId: _map(raw)['courierId'] as String? ?? '',
          courierName: _map(raw)['courierName'] as String? ?? '',
          kind: _map(raw)['courierKind'] == 'pool'
              ? CourierKind.pool
              : CourierKind.internal,
          aggregate: _aggregateFromWire(_map(raw)),
        ),
    ],
    poolOrders: [
      for (final raw in (data['poolOrders'] as List?) ?? const [])
        PoolOrderReportRow(
          orderId: _map(raw)['orderId'] as String? ?? '',
          orderNumber: _map(raw)['orderNumber'] as String? ?? '',
          courierName: _map(raw)['courierName'] as String? ?? '',
          neighborhoodName: _map(raw)['neighborhoodName'] as String? ?? '',
          amountMinorUnits:
              (_map(raw)['amountMinorUnits'] as num?)?.toInt() ?? 0,
          paymentMethodDisplayName:
              _map(raw)['paymentMethodDisplayName'] as String? ?? '',
          collectedAt: DateTime.parse(_map(raw)['collectedAt'] as String),
          deliveryMinutes: (_map(raw)['deliveryMinutes'] as num?)?.toDouble(),
        ),
    ],
    truncated: data['truncated'] == true,
  );
}

class FirebaseDeliveryOperationsGateway implements DeliveryOperationsGateway {
  FirebaseDeliveryOperationsGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  bool get _useRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    if (_useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw DeliveryOperationsException(error.code, error.message,
            detailCode: error.details?['code'] as String?);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      final details = error.details;
      throw DeliveryOperationsException(
          error.code, error.message ?? 'İşlem gerçekleştirilemedi.',
          detailCode: details is Map ? details['code'] as String? : null);
    }
  }

  @override
  Future<BranchDeliveryZones> listZones({
    required String organizationId,
    required String branchId,
  }) async =>
      branchDeliveryZonesFromWire(await _call('listBranchDeliveryZones',
          {'organizationId': organizationId, 'branchId': branchId}));

  @override
  Future<DeliveryZone> upsertZone({
    required String organizationId,
    required String branchId,
    required String neighborhoodName,
    String districtName = '',
    required int minimumOrderMinorUnits,
    int? estimatedDeliveryMinutes,
    bool enabled = true,
  }) async {
    final data = await _call('upsertBranchDeliveryZone', {
      'organizationId': organizationId,
      'branchId': branchId,
      'neighborhoodName': neighborhoodName,
      if (districtName.trim().isNotEmpty) 'districtName': districtName.trim(),
      'minimumOrderMinorUnits': minimumOrderMinorUnits,
      'estimatedDeliveryMinutes': estimatedDeliveryMinutes,
      'enabled': enabled,
    });
    return deliveryZoneFromWire(_map(data['zone']));
  }

  @override
  Future<CourierDeliveryReport> courierReport({
    required String organizationId,
    required String branchId,
    required DateTime from,
    required DateTime to,
  }) async =>
      courierDeliveryReportFromWire(await _call('getCourierDeliveryReport', {
        'organizationId': organizationId,
        'branchId': branchId,
        'fromIso': from.toUtc().toIso8601String(),
        'toIso': to.toUtc().toIso8601String(),
      }));
}

class UnavailableDeliveryOperationsGateway
    implements DeliveryOperationsGateway {
  const UnavailableDeliveryOperationsGateway();

  static const _error = DeliveryOperationsException(
      'unavailable', 'Sunucu bağlantısı hazır değil. Lütfen tekrar deneyin.');

  @override
  Future<BranchDeliveryZones> listZones({
    required String organizationId,
    required String branchId,
  }) async =>
      throw _error;

  @override
  Future<DeliveryZone> upsertZone({
    required String organizationId,
    required String branchId,
    required String neighborhoodName,
    String districtName = '',
    required int minimumOrderMinorUnits,
    int? estimatedDeliveryMinutes,
    bool enabled = true,
  }) async =>
      throw _error;

  @override
  Future<CourierDeliveryReport> courierReport({
    required String organizationId,
    required String branchId,
    required DateTime from,
    required DateTime to,
  }) async =>
      throw _error;
}
