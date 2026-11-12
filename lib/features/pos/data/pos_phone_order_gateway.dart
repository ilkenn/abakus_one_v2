import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';
import 'pos_action_gateway.dart' show PosDeviceContext;

/// 2026-11-11 (Faz 2) — the POS phone / counter order calls: a staff Gel-Al
/// order (`submitTakeawayOrder` `mode: "staffEntry"`), a staff Paket Servis
/// order (`submitStaffDeliveryOrder`) and the local customer book search
/// (`searchPosCustomers`). Routed through [RestCallableClient] on Windows,
/// like every other POS gateway — `cloud_functions` has no Windows
/// implementation, so the earlier direct calls could never succeed on the
/// Windows POS.
abstract interface class PosPhoneOrderGateway {
  Future<PosPhoneOrderResult> submitTakeaway({
    required PosDeviceContext ctx,
    required String submissionKey,
    required PosPhoneOrderContact contact,
    required List<Map<String, dynamic>> items,
    required String kitchenNote,
  });

  Future<PosPhoneOrderResult> submitDelivery({
    required PosDeviceContext ctx,
    required String submissionKey,
    required PosPhoneOrderContact contact,
    required PosDeliveryAddressInput address,
    required List<Map<String, dynamic>> items,
    required String courierNote,
    required String kitchenNote,
    required String paymentMethodId,
    required int deliveryFeeMinorUnits,
    String? plannedCourierId,
    bool belowMinimumApproved = false,
  });

  Future<List<PosCustomerBookEntry>> searchCustomers({
    required String organizationId,
    required String query,
  });

  /// 2026-11-12 (Faz 4, ADR-082) — KVKK: permanently deletes the local
  /// customer-book record [posCustomerId] and anonymizes that customer's
  /// shop-entered orders (`erasePosCustomer`, manager and above).
  Future<PosCustomerErasureResult> eraseCustomer({
    required String organizationId,
    required String posCustomerId,
    String? requestReference,
  });
}

class PosPhoneOrderException implements Exception {
  const PosPhoneOrderException(this.code, this.message, {this.details});
  final String code;
  final String message;

  /// The callable error's `details` (e.g. the minimum-order figures).
  final Map<String, dynamic>? details;

  /// `details.code`, e.g. `staffDelivery/below-minimum`.
  String? get detailCode => details?['code'] as String?;

  int? _int(String key) => (details?[key] as num?)?.toInt();
  int? get minimumOrderMinorUnits => _int('minimumOrderMinorUnits');
  int? get basketMinorUnits => _int('basketMinorUnits');
  int? get activeOrderCount => _int('activeOrderCount');

  @override
  String toString() => 'PosPhoneOrderException($code): $message';
}

class PosPhoneOrderContact {
  const PosPhoneOrderContact({
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.linkedCustomerId,
  });

  final String firstName;
  final String lastName;
  final String phone;

  /// The app customer staff picked from the directory, if any.
  final String? linkedCustomerId;
}

class PosDeliveryAddressInput {
  const PosDeliveryAddressInput({
    this.label = '',
    required this.neighborhoodName,
    required this.streetName,
    this.buildingNo = '',
    this.apartmentNo = '',
    this.floor = '',
    this.addressDescription = '',
  });

  final String label;
  final String neighborhoodName;
  final String streetName;
  final String buildingNo;
  final String apartmentNo;
  final String floor;
  final String addressDescription;

  factory PosDeliveryAddressInput.fromWire(Map<String, dynamic> data) {
    String text(String key) => (data[key] as String?) ?? '';
    return PosDeliveryAddressInput(
      label: text('label'),
      neighborhoodName: text('neighborhoodName'),
      streetName: text('streetName'),
      buildingNo: text('buildingNo'),
      apartmentNo: text('apartmentNo'),
      floor: text('floor'),
      addressDescription: text('addressDescription'),
    );
  }

  Map<String, dynamic> toWire() => {
        'label': label,
        'neighborhoodName': neighborhoodName,
        'streetName': streetName,
        'buildingNo': buildingNo,
        'apartmentNo': apartmentNo,
        'floor': floor,
        'addressDescription': addressDescription,
      };

  /// "Caferağa, Moda Caddesi, No 12, D 4"
  String get summary => [
        neighborhoodName,
        streetName,
        if (buildingNo.isNotEmpty) 'No $buildingNo',
        if (apartmentNo.isNotEmpty) 'D $apartmentNo',
        if (floor.isNotEmpty) 'Kat $floor',
      ].where((part) => part.isNotEmpty).join(', ');
}

class PosPhoneOrderResult {
  const PosPhoneOrderResult({
    required this.orderId,
    required this.orderNumber,
    required this.duplicate,
    this.estimatedDeliveryMinutes,
  });

  final String orderId;
  final String orderNumber;
  final bool duplicate;

  /// Faz 4 — the neighborhood rule's "Tahmini Teslimat Süresi", if any.
  final int? estimatedDeliveryMinutes;

  factory PosPhoneOrderResult.fromWire(Map<String, dynamic> data) =>
      PosPhoneOrderResult(
        orderId: data['orderId'] as String,
        orderNumber: data['orderNumber'] as String,
        duplicate: data['duplicate'] as bool? ?? false,
        estimatedDeliveryMinutes:
            (data['estimatedDeliveryMinutes'] as num?)?.toInt(),
      );
}

class PosCustomerErasureResult {
  const PosCustomerErasureResult({
    required this.erasureId,
    required this.anonymizedOrderCount,
  });

  final String erasureId;
  final int anonymizedOrderCount;
}

/// One `searchPosCustomers` row: a local-book record (full phone, remembered
/// addresses) or an app customer from the directory (masked phone only).
class PosCustomerBookEntry {
  const PosCustomerBookEntry({
    required this.isFromBook,
    required this.id,
    required this.displayName,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.phoneMasked,
    required this.addresses,
    required this.linkedCustomerId,
  });

  final bool isFromBook;
  final String id;
  final String displayName;
  final String firstName;
  final String lastName;

  /// Full E.164 number for a book record; `null` for an app customer.
  final String? phoneNumber;
  final String phoneMasked;

  /// Most recently used first.
  final List<PosDeliveryAddressInput> addresses;
  final String? linkedCustomerId;

  factory PosCustomerBookEntry.fromWire(Map<String, dynamic> data) =>
      PosCustomerBookEntry(
        isFromBook: data['source'] == 'book',
        id: data['id'] as String,
        displayName: data['displayName'] as String? ?? '',
        firstName: data['firstName'] as String? ?? '',
        lastName: data['lastName'] as String? ?? '',
        phoneNumber: data['phoneNumber'] as String?,
        phoneMasked: data['phoneMasked'] as String? ?? '',
        addresses: [
          for (final raw in (data['addresses'] as List?) ?? const [])
            PosDeliveryAddressInput.fromWire(
                Map<String, dynamic>.from(raw as Map)),
        ],
        linkedCustomerId: data['linkedCustomerId'] as String?,
      );
}

class FirebasePosPhoneOrderGateway implements PosPhoneOrderGateway {
  FirebasePosPhoneOrderGateway({RestCallableClient? restClient})
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
        throw PosPhoneOrderException(error.code, error.message,
            details: error.details);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      final details = error.details;
      throw PosPhoneOrderException(
          error.code, error.message ?? 'İşlem gerçekleştirilemedi.',
          details: details is Map ? Map<String, dynamic>.from(details) : null);
    }
  }

  Map<String, dynamic> _device(PosDeviceContext ctx) => {
        'organizationId': ctx.organizationId,
        'branchId': ctx.branchId,
        'deviceId': ctx.deviceId,
        'deviceSessionId': ctx.deviceSessionId,
      };

  @override
  Future<PosPhoneOrderResult> submitTakeaway({
    required PosDeviceContext ctx,
    required String submissionKey,
    required PosPhoneOrderContact contact,
    required List<Map<String, dynamic>> items,
    required String kitchenNote,
  }) async {
    final data = await _call('submitTakeawayOrder', {
      'mode': 'staffEntry',
      ..._device(ctx),
      'submissionKey': submissionKey,
      'contactFirstName': contact.firstName,
      'contactLastName': contact.lastName,
      'contactPhone': contact.phone,
      'kitchenNote': kitchenNote,
      'items': items,
    });
    return PosPhoneOrderResult.fromWire(data);
  }

  @override
  Future<PosPhoneOrderResult> submitDelivery({
    required PosDeviceContext ctx,
    required String submissionKey,
    required PosPhoneOrderContact contact,
    required PosDeliveryAddressInput address,
    required List<Map<String, dynamic>> items,
    required String courierNote,
    required String kitchenNote,
    required String paymentMethodId,
    required int deliveryFeeMinorUnits,
    String? plannedCourierId,
    bool belowMinimumApproved = false,
  }) async {
    final data = await _call('submitStaffDeliveryOrder', {
      ..._device(ctx),
      'submissionKey': submissionKey,
      'customer': {
        'firstName': contact.firstName,
        'lastName': contact.lastName,
        'phone': contact.phone,
        if (contact.linkedCustomerId != null)
          'linkedCustomerId': contact.linkedCustomerId,
      },
      'address': address.toWire(),
      'items': items,
      'courierNote': courierNote,
      'kitchenNote': kitchenNote,
      'paymentMethodId': paymentMethodId,
      'deliveryFeeMinorUnits': deliveryFeeMinorUnits,
      if (plannedCourierId != null) 'plannedCourierId': plannedCourierId,
      if (belowMinimumApproved) 'belowMinimumApproved': true,
    });
    return PosPhoneOrderResult.fromWire(data);
  }

  @override
  Future<List<PosCustomerBookEntry>> searchCustomers({
    required String organizationId,
    required String query,
  }) async {
    final data = await _call('searchPosCustomers', {
      'organizationId': organizationId,
      'query': query,
    });
    return [
      for (final raw in (data['customers'] as List?) ?? const [])
        PosCustomerBookEntry.fromWire(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  @override
  Future<PosCustomerErasureResult> eraseCustomer({
    required String organizationId,
    required String posCustomerId,
    String? requestReference,
  }) async {
    final data = await _call('erasePosCustomer', {
      'organizationId': organizationId,
      'posCustomerId': posCustomerId,
      if (requestReference != null && requestReference.trim().isNotEmpty)
        'requestReference': requestReference.trim(),
    });
    return PosCustomerErasureResult(
      erasureId: data['erasureId'] as String? ?? '',
      anonymizedOrderCount:
          (data['anonymizedOrderCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class UnavailablePosPhoneOrderGateway implements PosPhoneOrderGateway {
  const UnavailablePosPhoneOrderGateway();

  static const _error = PosPhoneOrderException(
      'unavailable', 'Sunucu bağlantısı hazır değil. Lütfen tekrar deneyin.');

  @override
  Future<PosPhoneOrderResult> submitTakeaway({
    required PosDeviceContext ctx,
    required String submissionKey,
    required PosPhoneOrderContact contact,
    required List<Map<String, dynamic>> items,
    required String kitchenNote,
  }) async =>
      throw _error;

  @override
  Future<PosPhoneOrderResult> submitDelivery({
    required PosDeviceContext ctx,
    required String submissionKey,
    required PosPhoneOrderContact contact,
    required PosDeliveryAddressInput address,
    required List<Map<String, dynamic>> items,
    required String courierNote,
    required String kitchenNote,
    required String paymentMethodId,
    required int deliveryFeeMinorUnits,
    String? plannedCourierId,
    bool belowMinimumApproved = false,
  }) async =>
      throw _error;

  @override
  Future<List<PosCustomerBookEntry>> searchCustomers({
    required String organizationId,
    required String query,
  }) async =>
      throw _error;

  @override
  Future<PosCustomerErasureResult> eraseCustomer({
    required String organizationId,
    required String posCustomerId,
    String? requestReference,
  }) async =>
      throw _error;
}
