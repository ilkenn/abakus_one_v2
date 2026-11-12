import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';
import 'pos_action_gateway.dart' show PosDeviceContext;

/// 2026-11-11 (Faz 2b) — "Kurye Döndü — Hesap Kapat": the server preview of
/// what a returning courier has to close (`getCourierSettlementPreview`) and
/// the one-call settlement (`settleCourierReturn`). REST on Windows, like
/// every POS gateway.
abstract interface class CourierSettlementGateway {
  Future<CourierSettlementPreview> preview({
    required PosDeviceContext ctx,
    required String courierId,
  });

  Future<CourierSettlementResult> settle({
    required PosDeviceContext ctx,
    required String courierId,
    required String cashSessionId,
    required String settlementKey,
    required List<CourierSettlementDelivery> deliveries,
    required int receivedCashMinorUnits,
    String? differenceReason,
  });
}

class CourierSettlementException implements Exception {
  const CourierSettlementException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'CourierSettlementException($code): $message';
}

class CourierSettlementOrder {
  const CourierSettlementOrder({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.customerName,
    required this.addressSummary,
    required this.amountDueMinorUnits,
    required this.plannedPaymentMethodId,
  });

  final String orderId;
  final String orderNumber;
  final String status;
  final String customerName;
  final String addressSummary;
  final int amountDueMinorUnits;
  final String? plannedPaymentMethodId;

  bool get isOpen => status == 'outForDelivery';

  factory CourierSettlementOrder.fromWire(Map<String, dynamic> data) =>
      CourierSettlementOrder(
        orderId: data['orderId'] as String,
        orderNumber: data['orderNumber'] as String? ?? '',
        status: data['status'] as String? ?? '',
        customerName: data['customerName'] as String? ?? '',
        addressSummary: data['addressSummary'] as String? ?? '',
        amountDueMinorUnits: (data['amountDueMinorUnits'] as num).toInt(),
        plannedPaymentMethodId: data['plannedPaymentMethodId'] as String?,
      );
}

class CourierSettlementPreview {
  const CourierSettlementPreview({
    required this.courierId,
    required this.courierName,
    required this.orders,
  });

  final String courierId;
  final String courierName;
  final List<CourierSettlementOrder> orders;

  factory CourierSettlementPreview.fromWire(Map<String, dynamic> data) =>
      CourierSettlementPreview(
        courierId: data['courierId'] as String,
        courierName: data['courierName'] as String? ?? '',
        orders: [
          for (final raw in (data['orders'] as List?) ?? const [])
            CourierSettlementOrder.fromWire(
                Map<String, dynamic>.from(raw as Map)),
        ],
      );
}

class CourierSettlementDelivery {
  const CourierSettlementDelivery({
    required this.orderId,
    required this.paymentMethodId,
    this.slipNumber,
  });

  final String orderId;
  final String paymentMethodId;
  final String? slipNumber;

  Map<String, dynamic> toWire() => {
        'orderId': orderId,
        'paymentMethodId': paymentMethodId,
        if (slipNumber != null && slipNumber!.trim().isNotEmpty)
          'slipNumber': slipNumber!.trim(),
      };
}

class CourierSettlementResult {
  const CourierSettlementResult({
    required this.settlementId,
    required this.duplicate,
    required this.differenceMinorUnits,
    required this.totalCollectedMinorUnits,
  });

  final String settlementId;
  final bool duplicate;
  final int differenceMinorUnits;
  final int totalCollectedMinorUnits;

  factory CourierSettlementResult.fromWire(Map<String, dynamic> data) =>
      CourierSettlementResult(
        settlementId: data['settlementId'] as String,
        duplicate: data['duplicate'] as bool? ?? false,
        differenceMinorUnits:
            (data['differenceMinorUnits'] as num?)?.toInt() ?? 0,
        totalCollectedMinorUnits:
            (data['totalCollectedMinorUnits'] as num?)?.toInt() ?? 0,
      );
}

class FirebaseCourierSettlementGateway implements CourierSettlementGateway {
  FirebaseCourierSettlementGateway({RestCallableClient? restClient})
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
        throw CourierSettlementException(error.code, error.message);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      throw CourierSettlementException(
          error.code, error.message ?? 'İşlem gerçekleştirilemedi.');
    }
  }

  Map<String, dynamic> _device(PosDeviceContext ctx) => {
        'organizationId': ctx.organizationId,
        'branchId': ctx.branchId,
        'deviceId': ctx.deviceId,
        'deviceSessionId': ctx.deviceSessionId,
      };

  @override
  Future<CourierSettlementPreview> preview({
    required PosDeviceContext ctx,
    required String courierId,
  }) async =>
      CourierSettlementPreview.fromWire(await _call(
          'getCourierSettlementPreview',
          {..._device(ctx), 'courierId': courierId}));

  @override
  Future<CourierSettlementResult> settle({
    required PosDeviceContext ctx,
    required String courierId,
    required String cashSessionId,
    required String settlementKey,
    required List<CourierSettlementDelivery> deliveries,
    required int receivedCashMinorUnits,
    String? differenceReason,
  }) async =>
      CourierSettlementResult.fromWire(await _call('settleCourierReturn', {
        ..._device(ctx),
        'courierId': courierId,
        'cashSessionId': cashSessionId,
        'settlementKey': settlementKey,
        'deliveries': [for (final d in deliveries) d.toWire()],
        'receivedCashMinorUnits': receivedCashMinorUnits,
        if (differenceReason != null) 'differenceReason': differenceReason,
      }));
}

class UnavailableCourierSettlementGateway implements CourierSettlementGateway {
  const UnavailableCourierSettlementGateway();

  static const _error = CourierSettlementException(
      'unavailable', 'Sunucu bağlantısı hazır değil. Lütfen tekrar deneyin.');

  @override
  Future<CourierSettlementPreview> preview({
    required PosDeviceContext ctx,
    required String courierId,
  }) async =>
      throw _error;

  @override
  Future<CourierSettlementResult> settle({
    required PosDeviceContext ctx,
    required String courierId,
    required String cashSessionId,
    required String settlementKey,
    required List<CourierSettlementDelivery> deliveries,
    required int receivedCashMinorUnits,
    String? differenceReason,
  }) async =>
      throw _error;
}
