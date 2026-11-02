import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../application/use_cases/moderate_customer_photo.dart';

/// 2026-10-27 — the real backend boundary for customer-photo moderation
/// mutations, mirroring `KitchenActionGateway`'s exact shape and reason:
/// `firestore.rules` denies every client write to `customerPhotos`
/// (`allow write: if false`) — the real, server-authoritative
/// `moderateCustomerPhoto` Cloud Function is the only writer. The existing
/// `ModerateCustomerPhoto` Dart use case (direct `_repository.save(...)`)
/// stays exactly as it was and is still used for the in-memory/pre-
/// Firebase path (dev/test) — this gateway is additive, not a
/// replacement, same split `FirestoreKitchenTicketRepository`/
/// `InMemoryKitchenTicketRepository` already established.
class CustomerPhotoModerationException implements Exception {
  const CustomerPhotoModerationException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'CustomerPhotoModerationException($code): $message';
}

abstract interface class CustomerPhotoModerationGateway {
  /// Moderates [photoId] via the real `moderateCustomerPhoto` callable —
  /// authorization, the status transition, clearing a public selection,
  /// and the audit entry are all server-authoritative; this call carries
  /// no client-side authorization decision of its own, unlike the in-
  /// memory `ModerateCustomerPhoto` use case it replaces once Firebase is
  /// ready.
  Future<void> moderate({
    required String photoId,
    required CustomerPhotoModerationAction action,
    String? rejectionReason,
  });
}

class FirebaseCustomerPhotoModerationGateway
    implements CustomerPhotoModerationGateway {
  const FirebaseCustomerPhotoModerationGateway();

  @override
  Future<void> moderate({
    required String photoId,
    required CustomerPhotoModerationAction action,
    String? rejectionReason,
  }) async {
    try {
      await functions.FirebaseFunctions.instance
          .httpsCallable('moderateCustomerPhoto')
          .call<Map<String, dynamic>>({
        'photoId': photoId,
        'action': action.name,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      throw CustomerPhotoModerationException(
        error.code,
        error.message ?? 'Fotoğraf denetim işlemi gerçekleştirilemedi.',
      );
    }
  }
}
