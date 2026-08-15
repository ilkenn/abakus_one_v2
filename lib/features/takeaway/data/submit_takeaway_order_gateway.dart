import 'package:cloud_functions/cloud_functions.dart' as functions;

/// What a successful `submitTakeawayOrder` call returns — the canonical
/// order identity the backend actually created (or reused, on a retry —
/// see [duplicate]). Deliberately minimal: the full order itself is read
/// back from `CanonicalOrderRepository` (already the established pattern,
/// `SubmitCustomerOrder`'s own callers do the same) rather than
/// duplicated into this response shape.
class SubmitTakeawayOrderResult {
  final String orderId;
  final String orderNumber;

  /// `true` when this call reused an already-existing order for the same
  /// (actor, submissionKey) pair rather than creating a new one — mirrors
  /// the backend's own idempotency contract (`docs/decisions.md` ADR-027
  /// Faz D.3). Informational only; the caller's behavior (read back the
  /// order, show the success screen) is identical either way.
  final bool duplicate;

  const SubmitTakeawayOrderResult({
    required this.orderId,
    required this.orderNumber,
    required this.duplicate,
  });
}

/// Thrown by [SubmitTakeawayOrderGateway.submitAuthenticatedOrder] for an
/// expected, non-exceptional-in-nature rejection — mirrors the Cloud
/// Function's own `HttpsError` codes verbatim
/// (`'unauthenticated'`/`'permission-denied'`/`'invalid-argument'`/
/// `'not-found'`/`'failed-precondition'`), the same reasoning as
/// `TableGuestSessionException`.
class SubmitTakeawayOrderException implements Exception {
  final String code;
  final String message;

  const SubmitTakeawayOrderException(this.code, this.message);

  @override
  String toString() => 'SubmitTakeawayOrderException($code): $message';
}

/// One line item in an authenticated takeaway order submission — either a
/// canonical menu product (with optional modifier selections) or a Bowl
/// Builder bowl (a flat list of canonical ingredient ids, one entry per
/// selected unit — a quantity-N ingredient appears N times, matching
/// `bowlBuilderSelectedModifiersProvider`'s own existing "N separate
/// entries" convention exactly, so no new aggregation step is needed at
/// this boundary).
///
/// Deliberately carries no price field of any kind — `functions/src/
/// submitTakeawayOrder.ts`'s own accepted request shape has none either;
/// this type structurally cannot be used to send a client-computed price,
/// not merely by developer discipline.
sealed class TakeawayOrderItem {
  const TakeawayOrderItem();
  Map<String, dynamic> toJson();
}

class TakeawayProductItem extends TakeawayOrderItem {
  final String productId;
  final int quantity;
  final List<({String groupId, String optionId})> selectedModifiers;
  final String note;

  const TakeawayProductItem({
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

class TakeawayBowlItem extends TakeawayOrderItem {
  final int quantity;
  final List<String> ingredientIds;
  final String note;

  const TakeawayBowlItem({
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

/// The one client-facing boundary onto the server-authoritative takeaway
/// order-creation backend (`submitTakeawayOrder` Cloud Function, Faz
/// D.3/D.3.1/D.4) — mirrors `TableGuestSessionGateway`'s exact shape
/// (narrow, mockable interface + real implementation; the real
/// `cloud_functions` SDK is unavailable under `flutter test`).
///
/// Both scenarios `submitTakeawayOrder` itself supports are exposed here:
/// the authenticated-app-customer path ([submitAuthenticatedOrder], Faz
/// D.3.1) and the QR-guest path ([submitGuestOrder], Faz D.4) — one
/// gateway, matching the backend's own "one callable, one pipeline, no
/// duplicated business logic" design; nothing about pricing/validation is
/// re-implemented client-side for either.
abstract interface class SubmitTakeawayOrderGateway {
  Future<SubmitTakeawayOrderResult> submitAuthenticatedOrder({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required DateTime pickupTime,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
  });

  /// The QR-guest scenario (Faz D.2/D.4) — [takeawaySessionId] is the
  /// only scope reference sent; `organizationId`/`restaurantId`/
  /// `branchId` are never accepted from the client here either. The
  /// backend derives them from the referenced `takeawayGuestSessions`
  /// document server-side, and forces `pickupMode: 'asap'`/
  /// `pickupTime: null` unconditionally for this branch — there is no
  /// pickup-time parameter on this method because there is nothing for
  /// one to do.
  Future<SubmitTakeawayOrderResult> submitGuestOrder({
    required String submissionKey,
    required String takeawaySessionId,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
  });
}

class FirebaseSubmitTakeawayOrderGateway implements SubmitTakeawayOrderGateway {
  const FirebaseSubmitTakeawayOrderGateway();

  @override
  Future<SubmitTakeawayOrderResult> submitAuthenticatedOrder({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required DateTime pickupTime,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('submitTakeawayOrder');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'submissionKey': submissionKey,
        'restaurantId': restaurantId,
        'branchId': branchId,
        'pickupMode': 'scheduled',
        'pickupTime': pickupTime.toIso8601String(),
        'items': [for (final item in items) item.toJson()],
        'contactFirstName': contactFirstName,
        'contactLastName': contactLastName,
        'contactPhone': contactPhone,
      });
      final data = result.data;
      return SubmitTakeawayOrderResult(
        orderId: data['orderId'] as String,
        orderNumber: data['orderNumber'] as String,
        duplicate: data['duplicate'] as bool,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw SubmitTakeawayOrderException(
        error.code,
        error.message ?? 'Takeaway order could not be submitted.',
      );
    }
  }

  @override
  Future<SubmitTakeawayOrderResult> submitGuestOrder({
    required String submissionKey,
    required String takeawaySessionId,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('submitTakeawayOrder');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'submissionKey': submissionKey,
        'takeawaySessionId': takeawaySessionId,
        'items': [for (final item in items) item.toJson()],
        'contactFirstName': contactFirstName,
        'contactLastName': contactLastName,
        'contactPhone': contactPhone,
      });
      final data = result.data;
      return SubmitTakeawayOrderResult(
        orderId: data['orderId'] as String,
        orderNumber: data['orderNumber'] as String,
        duplicate: data['duplicate'] as bool,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw SubmitTakeawayOrderException(
        error.code,
        error.message ?? 'Takeaway order could not be submitted.',
      );
    }
  }
}
