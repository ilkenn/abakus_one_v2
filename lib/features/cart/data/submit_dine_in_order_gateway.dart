import 'package:cloud_functions/cloud_functions.dart' as functions;

/// What a successful `submitDineInOrder` call returns — mirrors
/// `SubmitDeliveryOrderResult`'s exact shape/reasoning. The full order
/// itself is read back through `CanonicalOrderRepository`, never
/// reconstructed from this minimal response.
class SubmitDineInOrderResult {
  final String orderId;
  final String orderNumber;

  /// `true` when this call reused an already-existing order for the same
  /// (actor, submissionKey) pair — mirrors the backend's idempotency
  /// contract (`functions/src/submitDineInOrder.ts`).
  final bool duplicate;

  const SubmitDineInOrderResult({
    required this.orderId,
    required this.orderNumber,
    required this.duplicate,
  });
}

/// Thrown for an expected, non-exceptional-in-nature rejection — mirrors
/// the Cloud Function's own `HttpsError` codes verbatim, the same pattern
/// as `SubmitDeliveryOrderException`.
class SubmitDineInOrderException implements Exception {
  final String code;
  final String message;

  /// Boncuk Loyalty Program P7-D.1 (2026-08-24) — the stable, machine-
  /// readable reason from `functions/src/boncukRedemptionErrors.ts`'s
  /// `BONCUK_REDEMPTION_ERROR_REASONS`, carried through from the
  /// callable's `HttpsError.details.reason`. `null` for every non-Loyalty
  /// rejection.
  final String? boncukErrorReason;

  const SubmitDineInOrderException(
    this.code,
    this.message, {
    this.boncukErrorReason,
  });

  @override
  String toString() => 'SubmitDineInOrderException($code): $message'
      '${boncukErrorReason != null ? ' [reason: $boncukErrorReason]' : ''}';
}

String? _extractBoncukErrorReason(functions.FirebaseFunctionsException error) {
  final details = error.details;
  if (details is Map) {
    final reason = details['reason'];
    if (reason is String) return reason;
  }
  return null;
}

/// One line item in a dine-in order submission — either a canonical menu
/// product (with optional modifier selections) or a Bowl Builder bowl.
/// Mirrors `DeliveryOrderItem`'s exact shape and "no price field of any
/// kind" discipline.
sealed class DineInOrderItem {
  const DineInOrderItem();
  Map<String, dynamic> toJson();
}

class DineInProductItem extends DineInOrderItem {
  final String productId;
  final int quantity;
  final List<({String groupId, String optionId})> selectedModifiers;
  final String note;

  const DineInProductItem({
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

class DineInBowlItem extends DineInOrderItem {
  final int quantity;
  final List<String> ingredientIds;
  final String note;

  const DineInBowlItem({
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
/// `submitDineInOrder` Cloud Function — Boncuk Loyalty Program P7-D.1
/// (2026-08-24). The only creation path for a customer dine-in order (both
/// an anonymous table guest and a phone-verified customer at a table) —
/// there is no client-side price/scope field anywhere in this gateway's
/// request shape. `organizationId`/`restaurantId`/`branchId`/`tableId` are
/// never sent at all: the server derives every one of them from
/// [tableSessionId]'s own trusted `tableGuestSessions` record.
abstract interface class SubmitDineInOrderGateway {
  /// [selectedRewardId] is the ONLY catalog-reward-related value this
  /// method ever sends — mirrors `SubmitDeliveryOrderGateway.submit`'s own
  /// contract exactly. There is no `requestedBoncukAmount` parameter at
  /// all: dine-in cash Boncuk redemption is not a supported product
  /// behavior (`functions/src/submitDineInOrder.ts`'s own doc comment,
  /// BR-LOYALTY-019) — this gateway has structurally nothing to send for
  /// it, never a silently-ignored field.
  ///
  /// Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) —
  /// [selectedCampaignId] is the ONLY campaign-related value this method
  /// ever sends: which campaign the customer picked. There is structurally
  /// no parameter here for its discount amount/percentage, rule, version,
  /// or channel — the server resolves and re-validates every one of those
  /// itself (`functions/src/submitDineInOrder.ts`, P8-C.3). `null` (the
  /// default) means "no campaign requested." Mutually exclusive with
  /// [selectedRewardId] != null — sending both is rejected server-side (one
  /// order = one benefit). **LOCKED policy**: anonymous table guests can
  /// never use a campaign (mirrors the identical, already-existing guest
  /// exclusion on [selectedRewardId] above and the structural absence of
  /// any cash-Boncuk parameter) — the server rejects fail-closed for any
  /// non-phone-verified caller, regardless of this value.
  ///
  /// AP-3 continuation — [guestDisplayName] is sent only on request (the
  /// caller supplies it after catching a first rejection whose
  /// [SubmitDineInOrderException.boncukErrorReason] is exactly
  /// `"dineIn/guest-display-name-required"`, or proactively once already
  /// known) — mirrors `submitDineInOrder.ts`'s own `sanitizeGuestDisplayName`
  /// contract: `null`/absent is valid on every call except a guest's very
  /// first submission at a table, which the server rejects fail-closed
  /// until a name is supplied. Never used for `mode: "staffEntry"` (that
  /// flow's own sub-account naming is a POS-side concern, not this
  /// customer-facing gateway's).
  Future<SubmitDineInOrderResult> submit({
    required String submissionKey,
    required String tableSessionId,
    required List<DineInOrderItem> items,
    String customerNote = '',
    String? selectedRewardId,
    String? selectedCampaignId,
    String? guestDisplayName,
  });
}

class FirebaseSubmitDineInOrderGateway implements SubmitDineInOrderGateway {
  const FirebaseSubmitDineInOrderGateway();

  @override
  Future<SubmitDineInOrderResult> submit({
    required String submissionKey,
    required String tableSessionId,
    required List<DineInOrderItem> items,
    String customerNote = '',
    String? selectedRewardId,
    String? selectedCampaignId,
    String? guestDisplayName,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'submitDineInOrder',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'submissionKey': submissionKey,
        'tableSessionId': tableSessionId,
        'items': [for (final item in items) item.toJson()],
        'customerNote': customerNote,
        if (selectedRewardId != null) 'selectedRewardId': selectedRewardId,
        // Server-Authoritative Campaign Engine P8-C.3 — sent ONLY when
        // non-null, mirroring the server's own `sanitizeSelectedCampaignId`'s
        // "absent == null" contract exactly.
        if (selectedCampaignId != null)
          'selectedCampaignId': selectedCampaignId,
        if (guestDisplayName != null) 'guestDisplayName': guestDisplayName,
      });
      final data = result.data;
      return SubmitDineInOrderResult(
        orderId: data['orderId'] as String,
        orderNumber: data['orderNumber'] as String,
        duplicate: data['duplicate'] as bool,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw SubmitDineInOrderException(
        error.code,
        error.message ?? 'Sipariş gönderilemedi.',
        boncukErrorReason: _extractBoncukErrorReason(error),
      );
    }
  }
}
