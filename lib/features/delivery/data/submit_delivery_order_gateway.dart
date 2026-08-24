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

  /// Boncuk Loyalty Program P5-B (2026-08-24) — the stable, machine-readable
  /// reason from `functions/src/boncukRedemptionErrors.ts`'s
  /// `BONCUK_REDEMPTION_ERROR_REASONS` (e.g. `'boncuk/exceeds-max-usable'`),
  /// carried through from the callable's `HttpsError.details.reason` — the
  /// SAME shared vocabulary `SubmitTakeawayOrderException.boncukErrorReason`
  /// uses, never inferred from [code] alone. `null` for every non-Boncuk
  /// rejection, and for a Boncuk rejection whose `details` this gateway
  /// could not parse (fails safe to `null`, never fabricates a reason).
  final String? boncukErrorReason;

  const SubmitDeliveryOrderException(
    this.code,
    this.message, {
    this.boncukErrorReason,
  });

  @override
  String toString() => 'SubmitDeliveryOrderException($code): $message'
      '${boncukErrorReason != null ? ' [reason: $boncukErrorReason]' : ''}';
}

/// Extracts `error.details['reason']` defensively — mirrors
/// `submit_takeaway_order_gateway.dart`'s own `_extractBoncukErrorReason`
/// exactly; `details` is `dynamic` on
/// [functions.FirebaseFunctionsException], so this never assumes a shape.
String? _extractBoncukErrorReason(functions.FirebaseFunctionsException error) {
  final details = error.details;
  if (details is Map) {
    final reason = details['reason'];
    if (reason is String) return reason;
  }
  return null;
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
  /// Boncuk Loyalty Program P5-B (2026-08-24) — [requestedBoncukAmount] is
  /// the ONLY Boncuk-related value this method ever sends: a whole,
  /// non-negative Boncuk COUNT the customer explicitly chose. Mirrors
  /// `SubmitTakeawayOrderGateway.submitAuthenticatedOrder`'s own contract
  /// exactly — there is structurally no parameter here for a monetary
  /// value, a policy version, a max percentage, an available balance, or a
  /// remaining payable amount; the server resolves and re-validates every
  /// one of those itself (`functions/src/submitDeliveryOrder.ts`, P5-B).
  /// `0` (the default) means "no Boncuk requested," identical in effect to
  /// omitting the field entirely.
  Future<SubmitDeliveryOrderResult> submit({
    required String submissionKey,
    required String savedAddressId,
    required String paymentMethodId,
    required List<DeliveryOrderItem> items,
    ClientLocationEvidence? deviceLocation,
    String? deviceLocationUnavailableReason,
    int requestedBoncukAmount = 0,
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
    int requestedBoncukAmount = 0,
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
        // Boncuk Loyalty P5-B — sent ONLY when > 0, mirroring the server's
        // own `sanitizeRequestedBoncukAmount`'s "absent == 0" contract
        // exactly; omitting it for the common no-Boncuk case keeps the wire
        // payload identical to every pre-P5-B call.
        if (requestedBoncukAmount > 0)
          'requestedBoncukAmount': requestedBoncukAmount,
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
        boncukErrorReason: _extractBoncukErrorReason(error),
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
