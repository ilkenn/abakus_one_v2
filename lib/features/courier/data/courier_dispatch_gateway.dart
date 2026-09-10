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
}
