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

  /// Boncuk Loyalty Program P4-E-B (2026-08-22) — the stable,
  /// machine-readable reason from `functions/src/submitTakeawayOrder.ts`'s
  /// `BONCUK_REDEMPTION_ERROR_REASONS` (e.g.
  /// `'boncuk/exceeds-max-usable'`), carried through from the callable's
  /// `HttpsError.details.reason` — never inferred from [code] alone. [code]
  /// on its own is insufficient here: `'invalid-argument'`/
  /// `'failed-precondition'` are ALSO thrown for entirely unrelated
  /// validation in this same callable (contact fields, pickup time, branch
  /// scope, ...), so a caller that needs to know specifically "the Boncuk
  /// selection is now invalid" must branch on this field, never on [code].
  /// `null` for every non-Boncuk rejection, and for a Boncuk rejection
  /// whose `details` this gateway could not parse (fails safe to `null`,
  /// never fabricates a reason).
  final String? boncukErrorReason;

  const SubmitTakeawayOrderException(
    this.code,
    this.message, {
    this.boncukErrorReason,
  });

  @override
  String toString() => 'SubmitTakeawayOrderException($code): $message'
      '${boncukErrorReason != null ? ' [reason: $boncukErrorReason]' : ''}';
}

/// Extracts `error.details['reason']` defensively — `details` is `dynamic`
/// on [functions.FirebaseFunctionsException] (it round-trips whatever the
/// callable's own `HttpsError` constructor was given, or `null` if it gave
/// nothing), so this never assumes a shape; any mismatch resolves to `null`
/// rather than throwing while already handling an error.
String? _extractBoncukErrorReason(functions.FirebaseFunctionsException error) {
  final details = error.details;
  if (details is Map) {
    final reason = details['reason'];
    if (reason is String) return reason;
  }
  return null;
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
  /// Boncuk Loyalty Program P4-E-B (2026-08-22) — [requestedBoncukAmount]
  /// is the ONLY Boncuk-related value this method ever sends: a whole,
  /// non-negative Boncuk COUNT the customer explicitly chose. There is
  /// structurally no parameter here for a monetary value, a policy
  /// version, a max percentage, an available balance, or a remaining
  /// payable amount — the server resolves and re-validates every one of
  /// those itself (`functions/src/submitTakeawayOrder.ts`, P4-B). `0` (the
  /// default) means "no Boncuk requested," identical in effect to omitting
  /// the field entirely.
  /// Boncuk Loyalty Program P7-C (2026-08-24) — [selectedRewardId] is the
  /// ONLY reward-related value this method ever sends: which catalog
  /// reward the customer picked. There is structurally no parameter here
  /// for its Boncuk cost, its title, or which product it covers — the
  /// server resolves and re-validates every one of those itself
  /// (`functions/src/submitTakeawayOrder.ts`, P7-C). `null` (the default)
  /// means "no reward requested." Mutually exclusive with
  /// [requestedBoncukAmount] > 0 — sending both is rejected server-side.
  Future<SubmitTakeawayOrderResult> submitAuthenticatedOrder({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required DateTime pickupTime,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
    int requestedBoncukAmount = 0,
    String? selectedRewardId,
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
    int requestedBoncukAmount = 0,
    String? selectedRewardId,
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
        // Boncuk Loyalty P4-E-B — sent ONLY when > 0, mirroring the
        // server's own `sanitizeRequestedBoncukAmount`'s "absent == 0"
        // contract exactly; omitting it for the common no-Boncuk case
        // keeps the wire payload identical to every pre-P4-E-B call.
        if (requestedBoncukAmount > 0)
          'requestedBoncukAmount': requestedBoncukAmount,
        // Boncuk Loyalty P7-C — sent ONLY when non-null, mirroring the
        // server's own `sanitizeSelectedRewardId`'s "absent == null"
        // contract exactly.
        if (selectedRewardId != null) 'selectedRewardId': selectedRewardId,
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
        boncukErrorReason: _extractBoncukErrorReason(error),
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
