import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../../../shared/models/courier_type.dart';

/// AP-6 Sprint 2 — the real backend boundary for courier dispatch actions
/// (`setCourier`/`assignCourierToOrder`/`markCourierReturned` callables),
/// mirroring `TakeawayOperationsGateway`'s exact shape: an interface, a
/// [FirebaseCourierDispatchGateway] backed by the real callables, and a
/// fail-closed [UnavailableCourierDispatchGateway] for when Firebase isn't
/// ready yet — never a silent local simulation.
class CourierDispatchException implements Exception {
  const CourierDispatchException(this.code, this.message, {this.reason});
  final String code;
  final String message;

  /// Stable `details.reason` value when the server provided one (e.g.
  /// `"courier/marketplace-immutable"`) — see `assignCourierToOrder.ts`'s
  /// own doc comment. `null` for a plain validation/auth error with no
  /// dedicated reason.
  final String? reason;

  @override
  String toString() => 'CourierDispatchException($code): $message';
}

class CourierAssignmentResult {
  const CourierAssignmentResult({
    required this.orderId,
    required this.courierId,
    required this.trackingToken,
    required this.status,
  });

  final String orderId;
  final String courierId;
  final String trackingToken;
  final String status;
}

/// AP-6 Sprint 3 — the result of `registerConsortiumOrder`.
class ConsortiumOrderRegistrationResult {
  const ConsortiumOrderRegistrationResult({
    required this.orderId,
    required this.orderNumber,
  });

  final String orderId;
  final String orderNumber;
}

abstract interface class CourierDispatchGateway {
  /// The dispatch dialog's own lightweight inline quick-add — see
  /// `setCourier.ts`'s own doc comment for why no full roster-management
  /// screen exists this sprint. `courierId` omitted creates a new courier;
  /// supplied, it's an idempotent upsert/edit.
  Future<String> setCourier({
    required String organizationId,
    required String branchId,
    required String displayName,
    required String phoneNumber,
    CourierType type = CourierType.internal,
    String? courierId,
  });

  Future<CourierAssignmentResult> assignCourierToOrder({
    required String orderId,
    required String courierId,
  });

  Future<void> markCourierReturned({required String courierId});

  /// AP-6 Sprint 3 — registers a consortium/external-merchant delivery
  /// order (see `registerConsortiumOrder.ts`'s own doc comment for the
  /// exact document shape this produces). The dispatch console's own
  /// lightweight inline "Dış Restoran Siparişi Kaydet" quick-add calls
  /// this — no full roster-management screen exists this sprint, same
  /// scoping precedent as [setCourier].
  Future<ConsortiumOrderRegistrationResult> registerConsortiumOrder({
    required String organizationId,
    required String branchId,
    required String merchantId,
    required String merchantName,
    required String pickupAddress,
    required int consortiumDeliveryFeeMinorUnits,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
    required String dropoffAddressDescription,
    String? dropoffNeighborhoodName,
    String? dropoffProvinceName,
    String? dropoffDistrictName,
  });

  /// AP-6 Sprint 3 — the multi-pickup/multi-drop sibling of
  /// [assignCourierToOrder]: assigns every order in [orderIds] to
  /// [courierId] in one call, preserving [orderIds]'s own order as the
  /// courier's pickup/drop sequence (see `batchAssignCourierToOrders.ts`'s
  /// own doc comment). Fails the whole batch closed on any single invalid
  /// order — never a partial-batch result.
  Future<List<CourierAssignmentResult>> batchAssignCourierToOrders({
    required List<String> orderIds,
    required String courierId,
  });
}

class FirebaseCourierDispatchGateway implements CourierDispatchGateway {
  const FirebaseCourierDispatchGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw CourierDispatchException(
      error.code,
      error.message ?? 'Kurye işlemi gerçekleştirilemedi.',
      reason: (error.details is Map)
          ? (error.details as Map)['reason'] as String?
          : null,
    );
  }

  functions.HttpsCallable _fn(String name) =>
      functions.FirebaseFunctions.instance.httpsCallable(name);

  @override
  Future<String> setCourier({
    required String organizationId,
    required String branchId,
    required String displayName,
    required String phoneNumber,
    CourierType type = CourierType.internal,
    String? courierId,
  }) async {
    try {
      final result = await _fn('setCourier').call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'displayName': displayName,
        'phoneNumber': phoneNumber,
        'type': type.name,
        if (courierId != null) 'courierId': courierId,
      });
      return result.data['courierId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<CourierAssignmentResult> assignCourierToOrder({
    required String orderId,
    required String courierId,
  }) async {
    try {
      final result =
          await _fn('assignCourierToOrder').call<Map<String, dynamic>>({
        'orderId': orderId,
        'courierId': courierId,
      });
      final data = result.data;
      return CourierAssignmentResult(
        orderId: data['orderId'] as String,
        courierId: data['courierId'] as String,
        trackingToken: data['trackingToken'] as String,
        status: data['status'] as String,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> markCourierReturned({required String courierId}) async {
    try {
      await _fn('markCourierReturned')
          .call<Map<String, dynamic>>({'courierId': courierId});
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<ConsortiumOrderRegistrationResult> registerConsortiumOrder({
    required String organizationId,
    required String branchId,
    required String merchantId,
    required String merchantName,
    required String pickupAddress,
    required int consortiumDeliveryFeeMinorUnits,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
    required String dropoffAddressDescription,
    String? dropoffNeighborhoodName,
    String? dropoffProvinceName,
    String? dropoffDistrictName,
  }) async {
    try {
      final result =
          await _fn('registerConsortiumOrder').call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'merchantId': merchantId,
        'merchantName': merchantName,
        'pickupAddress': pickupAddress,
        'consortiumDeliveryFeeMinorUnits': consortiumDeliveryFeeMinorUnits,
        'contactFirstName': contactFirstName,
        'contactLastName': contactLastName,
        'contactPhone': contactPhone,
        'dropoffAddressDescription': dropoffAddressDescription,
        if (dropoffNeighborhoodName != null)
          'dropoffNeighborhoodName': dropoffNeighborhoodName,
        if (dropoffProvinceName != null) 'dropoffProvinceName': dropoffProvinceName,
        if (dropoffDistrictName != null) 'dropoffDistrictName': dropoffDistrictName,
      });
      final data = result.data;
      return ConsortiumOrderRegistrationResult(
        orderId: data['orderId'] as String,
        orderNumber: data['orderNumber'] as String,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<CourierAssignmentResult>> batchAssignCourierToOrders({
    required List<String> orderIds,
    required String courierId,
  }) async {
    try {
      final result =
          await _fn('batchAssignCourierToOrders').call<Map<String, dynamic>>({
        'orderIds': orderIds,
        'courierId': courierId,
      });
      final results = result.data['results'] as List<dynamic>;
      return [
        for (final raw in results)
          CourierAssignmentResult(
            orderId: (raw as Map)['orderId'] as String,
            courierId: courierId,
            trackingToken: raw['trackingToken'] as String,
            status: raw['status'] as String,
          ),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

class UnavailableCourierDispatchGateway implements CourierDispatchGateway {
  const UnavailableCourierDispatchGateway();

  Never _unavailable() => throw const CourierDispatchException(
        'unavailable',
        'Kurye dispatch servisi şu anda kullanılamıyor.',
      );

  @override
  Future<String> setCourier({
    required String organizationId,
    required String branchId,
    required String displayName,
    required String phoneNumber,
    CourierType type = CourierType.internal,
    String? courierId,
  }) async =>
      _unavailable();

  @override
  Future<CourierAssignmentResult> assignCourierToOrder({
    required String orderId,
    required String courierId,
  }) async =>
      _unavailable();

  @override
  Future<void> markCourierReturned({required String courierId}) async =>
      _unavailable();

  @override
  Future<ConsortiumOrderRegistrationResult> registerConsortiumOrder({
    required String organizationId,
    required String branchId,
    required String merchantId,
    required String merchantName,
    required String pickupAddress,
    required int consortiumDeliveryFeeMinorUnits,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
    required String dropoffAddressDescription,
    String? dropoffNeighborhoodName,
    String? dropoffProvinceName,
    String? dropoffDistrictName,
  }) async =>
      _unavailable();

  @override
  Future<List<CourierAssignmentResult>> batchAssignCourierToOrders({
    required List<String> orderIds,
    required String courierId,
  }) async =>
      _unavailable();
}
