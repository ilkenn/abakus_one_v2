import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../domain/models/reservation_area.dart';
import '../domain/models/reservation_availability_slot.dart';
import '../domain/models/reservation_branch_info.dart';

/// Thrown by every [ReservationGateway] method for an expected,
/// non-exceptional-in-nature rejection — mirrors the Cloud Function's own
/// `HttpsError` codes verbatim, the same shape
/// `SubmitTakeawayOrderException`/`TableGuestSessionException` already
/// establish in this codebase.
class ReservationException implements Exception {
  final String code;
  final String message;

  /// Boncuk Loyalty Program P6-B (2026-08-24) — the stable, machine-readable
  /// reason from `functions/src/boncukRedemptionErrors.ts`'s
  /// `BONCUK_REDEMPTION_ERROR_REASONS` (e.g. `'boncuk/exceeds-max-usable'`),
  /// carried through from the callable's `HttpsError.details.reason` — the
  /// SAME shared vocabulary `SubmitTakeawayOrderException.boncukErrorReason`/
  /// `SubmitDeliveryOrderException.boncukErrorReason` use, never inferred
  /// from [code] alone. `null` for every non-Boncuk rejection, and for a
  /// Boncuk rejection whose `details` this gateway could not parse (fails
  /// safe to `null`, never fabricates a reason).
  final String? boncukErrorReason;

  const ReservationException(this.code, this.message, {this.boncukErrorReason});

  @override
  String toString() => 'ReservationException($code): $message'
      '${boncukErrorReason != null ? ' [reason: $boncukErrorReason]' : ''}';
}

/// Extracts `error.details['reason']` defensively — mirrors
/// `submit_takeaway_order_gateway.dart`'s/`submit_delivery_order_gateway
/// .dart`'s own `_extractBoncukErrorReason` exactly; `details` is `dynamic`
/// on [functions.FirebaseFunctionsException], so this never assumes a shape.
String? _extractBoncukErrorReason(functions.FirebaseFunctionsException error) {
  final details = error.details;
  if (details is Map) {
    final reason = details['reason'];
    if (reason is String) return reason;
  }
  return null;
}

/// One preorder line item — structurally identical to
/// `features/takeaway/data/submit_takeaway_order_gateway.dart`'s
/// `TakeawayOrderItem` (the backend's own `submitReservation.ts` accepts
/// the exact same `{kind, productId|quantity+ingredientIds, ...}` shape
/// `submitTakeawayOrder.ts` does — both mirror `reservationPreorder.ts`
/// reusing `takeawayCatalog.ts`/`takeawayPricing.ts` as-is). Deliberately
/// a small, independent duplication rather than a cross-feature import of
/// `takeaway`'s own type — mirrors that same backend module's own
/// precedent of duplicating `submitTakeawayOrder.ts`'s request-shape
/// helpers locally rather than importing across feature boundaries.
/// Carries no price field of any kind, structurally — the backend is
/// always the sole price authority.
sealed class ReservationPreorderItem {
  const ReservationPreorderItem();
  Map<String, dynamic> toJson();
}

class ReservationPreorderProductItem extends ReservationPreorderItem {
  final String productId;
  final int quantity;
  final List<({String groupId, String optionId})> selectedModifiers;
  final String note;

  const ReservationPreorderProductItem({
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

class ReservationPreorderBowlItem extends ReservationPreorderItem {
  final int quantity;
  final List<String> ingredientIds;
  final String note;

  const ReservationPreorderBowlItem({
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

/// What a successful `submitReservation` call returns.
class SubmitReservationResult {
  const SubmitReservationResult({
    required this.reservationId,
    required this.status,
    required this.requestedAvailabilityAtSubmission,
    required this.preorderOrderId,
    required this.duplicate,
  });

  final String reservationId;
  final String status;
  final String requestedAvailabilityAtSubmission;
  final String? preorderOrderId;
  final bool duplicate;
}

/// The one client-facing boundary onto the server-authoritative
/// reservation backend (`submitReservation`/`respondToProposedChange`/
/// `getReservationBranchInfo`/`getReservationAvailability` Cloud
/// Functions, Faz R.1A-R.2) — mirrors `SubmitTakeawayOrderGateway`'s exact
/// shape (narrow, mockable interface + real implementation; the real
/// `cloud_functions` SDK is unavailable under `flutter test`).
abstract interface class ReservationGateway {
  /// Boncuk Loyalty Program P6-B (2026-08-24) — [requestedBoncukAmount] is
  /// the ONLY Boncuk-related value this method ever sends: a whole,
  /// non-negative Boncuk COUNT the customer explicitly chose. Mirrors
  /// `SubmitTakeawayOrderGateway`/`SubmitDeliveryOrderGateway`'s own
  /// contract exactly — there is structurally no parameter here for a
  /// monetary value, a policy version, a max percentage, an available
  /// balance, or a remaining payable amount; the server resolves and
  /// re-validates every one of those itself
  /// (`functions/src/submitReservation.ts`, P6-B). `0` (the default) means
  /// "no Boncuk requested," identical in effect to omitting the field
  /// entirely. **Only ever meaningful when [preorderItems] is non-empty** —
  /// Boncuk redemption applies against the preorder, never the reservation
  /// itself (there is nothing to redeem against a table-only booking).
  Future<SubmitReservationResult> submitReservation({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required String areaId,
    required int partySize,
    required DateTime requestedTime,
    required String contactFirstName,
    required String contactLastName,
    List<ReservationPreorderItem>? preorderItems,
    int requestedBoncukAmount = 0,

    /// Boncuk Loyalty Program P7-D (2026-08-24) — the customer's optional
    /// catalog-reward selection, mirroring [requestedBoncukAmount]'s own
    /// "only ever meaningful when [preorderItems] is non-empty" contract
    /// and nested inside the same `preorder` wire map for the identical
    /// reason. Mutually exclusive with [requestedBoncukAmount] > 0 — the
    /// server rejects a request that sets both.
    String? selectedRewardId,
  });

  Future<void> respondToProposedChange({
    required String reservationId,
    required String proposalId,
    required bool accept,
  });

  /// Faz R.3B — customer self-cancellation. Server-side authority always
  /// decides eligibility (own-reservation ownership, the customer
  /// cancellation cutoff, released-preorder lock) — this method has no
  /// client-side pre-check of its own; a rejection surfaces as a
  /// [ReservationException] the caller maps to copy via
  /// `reservationErrorMessage`.
  Future<void> cancelReservation({
    required String reservationId,
    String? reasonCode,
  });

  Future<ReservationBranchInfo> getReservationBranchInfo({
    required String restaurantId,
    required String branchId,
  });

  Future<List<ReservationAvailabilitySlot>> getReservationAvailability({
    required String restaurantId,
    required String branchId,
    required String areaId,
    required String date,
    required int partySize,
  });
}

class FirebaseReservationGateway implements ReservationGateway {
  const FirebaseReservationGateway();

  @override
  Future<SubmitReservationResult> submitReservation({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required String areaId,
    required int partySize,
    required DateTime requestedTime,
    required String contactFirstName,
    required String contactLastName,
    List<ReservationPreorderItem>? preorderItems,
    int requestedBoncukAmount = 0,
    String? selectedRewardId,
  }) async {
    final callable =
        functions.FirebaseFunctions.instance.httpsCallable('submitReservation');
    final hasPreorder = preorderItems != null && preorderItems.isNotEmpty;
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'submissionKey': submissionKey,
        'restaurantId': restaurantId,
        'branchId': branchId,
        'areaId': areaId,
        'partySize': partySize,
        'requestedTime': requestedTime.toIso8601String(),
        'contactFirstName': contactFirstName,
        'contactLastName': contactLastName,
        if (hasPreorder)
          'preorder': {
            'items': [for (final item in preorderItems) item.toJson()],
            // Boncuk Loyalty P6-B — sent ONLY when > 0, mirroring the
            // server's own `sanitizeRequestedBoncukAmount`'s "absent == 0"
            // contract exactly; nested inside `preorder` since it is only
            // ever meaningful alongside one.
            if (requestedBoncukAmount > 0)
              'requestedBoncukAmount': requestedBoncukAmount,
            // Boncuk Loyalty P7-D — same nesting reasoning, for the
            // mutually exclusive catalog-reward selection.
            if (selectedRewardId != null) 'selectedRewardId': selectedRewardId,
          },
      });
      final data = result.data;
      return SubmitReservationResult(
        reservationId: data['reservationId'] as String,
        status: data['status'] as String,
        requestedAvailabilityAtSubmission:
            data['requestedAvailabilityAtSubmission'] as String,
        preorderOrderId: data['preorderOrderId'] as String?,
        duplicate: data['duplicate'] as bool,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw ReservationException(
        error.code,
        error.message ?? 'Reservation could not be submitted.',
        boncukErrorReason: _extractBoncukErrorReason(error),
      );
    }
  }

  @override
  Future<void> respondToProposedChange({
    required String reservationId,
    required String proposalId,
    required bool accept,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('respondToProposedChange');
    try {
      await callable.call<Map<String, dynamic>>({
        'reservationId': reservationId,
        'proposalId': proposalId,
        'action': accept ? 'accept' : 'reject',
      });
    } on functions.FirebaseFunctionsException catch (error) {
      throw ReservationException(
        error.code,
        error.message ?? 'Could not respond to the proposed change.',
      );
    }
  }

  @override
  Future<void> cancelReservation({
    required String reservationId,
    String? reasonCode,
  }) async {
    final callable =
        functions.FirebaseFunctions.instance.httpsCallable('cancelReservation');
    try {
      await callable.call<Map<String, dynamic>>({
        'reservationId': reservationId,
        if (reasonCode != null) 'reasonCode': reasonCode,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      throw ReservationException(
        error.code,
        error.message ?? 'Reservation could not be cancelled.',
      );
    }
  }

  @override
  Future<ReservationBranchInfo> getReservationBranchInfo({
    required String restaurantId,
    required String branchId,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('getReservationBranchInfo');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'restaurantId': restaurantId,
        'branchId': branchId,
      });
      final data = result.data;
      final policyJson = Map<String, dynamic>.from(data['policy'] as Map);
      final areasJson = List<Map<String, dynamic>>.from(
        (data['areas'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      return ReservationBranchInfo(
        policy: ReservationBranchPolicy(
          maxPartySize: policyJson['maxPartySize'] as int,
          slotIntervalMinutes: policyJson['slotIntervalMinutes'] as int,
          reservationDurationMinutes:
              policyJson['reservationDurationMinutes'] as int,
          bookingHorizonDays: policyJson['bookingHorizonDays'] as int,
          timezone: policyJson['timezone'] as String,
          minimumAdvanceMinutes: policyJson['minimumAdvanceMinutes'] as int,
        ),
        areas: [
          for (final area in areasJson)
            ReservationArea(
              id: area['id'] as String,
              displayName: area['displayName'] as String,
            ),
        ],
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw ReservationException(
        error.code,
        error.message ?? 'Reservation branch info could not be loaded.',
      );
    }
  }

  @override
  Future<List<ReservationAvailabilitySlot>> getReservationAvailability({
    required String restaurantId,
    required String branchId,
    required String areaId,
    required String date,
    required int partySize,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('getReservationAvailability');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'restaurantId': restaurantId,
        'branchId': branchId,
        'areaId': areaId,
        'date': date,
        'partySize': partySize,
      });
      final slots = List<Map<String, dynamic>>.from(
        (result.data['slots'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
      return [
        for (final slot in slots)
          ReservationAvailabilitySlot(
            time: DateTime.parse(slot['time'] as String),
            available: slot['available'] as bool,
          ),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      throw ReservationException(
        error.code,
        error.message ?? 'Reservation availability could not be loaded.',
      );
    }
  }
}
