import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../../../core/fraud/domain/fraud_evidence.dart';

/// What a successful `submitDeliveryOrder` call returns — mirrors
/// `SubmitTakeawayOrderResult`'s exact shape/reasoning. The full order
/// itself is read back through `CanonicalOrderRepository`, never
/// reconstructed from this minimal response.
class SubmitDeliveryOrderResult {
  final String orderId;
  final String orderNumber;

  /// `true` when this call reused an already-existing order for the same
  /// (actor, submissionKey) pair — mirrors the backend's idempotency
  /// contract (Paket Servis P.3, `submitDeliveryOrder.ts`).
  final bool duplicate;

  const SubmitDeliveryOrderResult({
    required this.orderId,
    required this.orderNumber,
    required this.duplicate,
  });
}

/// Thrown for an expected, non-exceptional-in-nature rejection — mirrors
/// the Cloud Function's own `HttpsError` codes verbatim, the same pattern
/// as `SubmitTakeawayOrderException`.
class SubmitDeliveryOrderException implements Exception {
  final String code;
  final String message;

  const SubmitDeliveryOrderException(this.code, this.message);

  @override
  String toString() => 'SubmitDeliveryOrderException($code): $message';
}

/// One line item in a delivery order submission — either a canonical menu
/// product (with optional modifier selections) or a Bowl Builder bowl.
/// Mirrors `TakeawayOrderItem`'s exact shape and "no price field of any
/// kind" discipline — `submitDeliveryOrder.ts`'s accepted request shape has
/// none either.
sealed class DeliveryOrderItem {
  const DeliveryOrderItem();
  Map<String, dynamic> toJson();
}

class DeliveryProductItem extends DeliveryOrderItem {
  final String productId;
  final int quantity;
  final List<({String groupId, String optionId})> selectedModifiers;
  final String note;

  const DeliveryProductItem({
    required this.productId,
    required this.quantity,
    this.selectedModifiers = const [],
    this.note = '',
  });

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'product',
        'productId': productId,
        'quantity': quantity,
        'selectedModifiers': [
          for (final modifier in selectedModifiers)
            {'groupId': modifier.groupId, 'optionId': modifier.optionId},
        ],
        'note': note,
      };
}

class DeliveryBowlItem extends DeliveryOrderItem {
  final int quantity;
  final List<String> ingredientIds;
  final String note;

  const DeliveryBowlItem({
    required this.quantity,
    required this.ingredientIds,
    this.note = '',
  });

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'bowl',
        'quantity': quantity,
        'ingredientIds': ingredientIds,
        'note': note,
      };
}

/// The one client-facing boundary onto the server-authoritative
/// `submitDeliveryOrder` Cloud Function — Paket Servis P.3. The only
/// creation path for a customer delivery order; there is no client-side
/// price/scope/risk field anywhere in this gateway's request shape.
///
/// [deviceLocation]/[deviceLocationUnavailableReason] carry the FRAUD-F.2
/// order-submit location candidate — mutually exclusive, both optional.
/// **Callers must capture this candidate at most once per submission
/// attempt and reuse it across retries of the same [submissionKey]** — this
/// gateway performs no capture itself; it only forwards whatever candidate
/// the caller already resolved, exactly like `SavedAddressRepository.save`
/// does for the FRAUD-F.1 address-save candidate.
abstract interface class SubmitDeliveryOrderGateway {
  Future<SubmitDeliveryOrderResult> submit({
    required String submissionKey,
    required String savedAddressId,
    required String paymentMethodId,
    required List<DeliveryOrderItem> items,
    ClientLocationEvidence? deviceLocation,
    String? deviceLocationUnavailableReason,
  });
}

class FirebaseSubmitDeliveryOrderGateway implements SubmitDeliveryOrderGateway {
  const FirebaseSubmitDeliveryOrderGateway();

  @override
  Future<SubmitDeliveryOrderResult> submit({
    required String submissionKey,
    required String savedAddressId,
    required String paymentMethodId,
    required List<DeliveryOrderItem> items,
    ClientLocationEvidence? deviceLocation,
    String? deviceLocationUnavailableReason,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'submitDeliveryOrder',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'submissionKey': submissionKey,
        'savedAddressId': savedAddressId,
        'paymentMethodId': paymentMethodId,
        'items': [for (final item in items) item.toJson()],
        'deviceLocationCandidate': _serializeDeviceLocationCandidate(
          deviceLocation,
          deviceLocationUnavailableReason,
        ),
      });
      final data = result.data;
      return SubmitDeliveryOrderResult(
        orderId: data['orderId'] as String,
        orderNumber: data['orderNumber'] as String,
        duplicate: data['duplicate'] as bool,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw SubmitDeliveryOrderException(
        error.code,
        error.message ?? 'Sipariş gönderilemedi.',
      );
    }
  }

  /// Mirrors `FirestoreSavedAddressRepository._serializeDeviceLocationCandidate`
  /// verbatim (FRAUD-F.1's own established shape) — the server independently
  /// decides availability/incompleteness, never trusting this at face value.
  Map<String, dynamic> _serializeDeviceLocationCandidate(
    ClientLocationEvidence? deviceLocation,
    String? unavailableReason,
  ) {
    if (deviceLocation == null) {
      return {
        'status': 'unavailable',
        if (unavailableReason != null) 'unavailableReason': unavailableReason,
      };
    }
    return {
      'status': 'available',
      'latitude': deviceLocation.latitude,
      'longitude': deviceLocation.longitude,
      'accuracyMeters': deviceLocation.accuracyMeters,
      'clientCapturedAt': deviceLocation.clientCapturedAt.toIso8601String(),
      'mockLocationStatus': deviceLocation.mockLocationStatus.name,
      'permissionState': deviceLocation.permissionState,
      'precisionState': deviceLocation.precisionState,
    };
  }
}
