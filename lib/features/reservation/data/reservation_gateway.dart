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

  const ReservationException(this.code, this.message);

  @override
  String toString() => 'ReservationException($code): $message';
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
  }) async {
    final callable =
        functions.FirebaseFunctions.instance.httpsCallable('submitReservation');
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
        if (preorderItems != null && preorderItems.isNotEmpty)
          'preorder': {
            'items': [for (final item in preorderItems) item.toJson()],
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
