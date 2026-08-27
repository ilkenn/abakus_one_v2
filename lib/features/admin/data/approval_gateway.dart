import 'package:cloud_functions/cloud_functions.dart' as functions;

class ApprovalException implements Exception {
  const ApprovalException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => 'ApprovalException($code): $message';
}

/// AP-2 final wiring — the real mutation surface for the Approval Inbox.
/// Deliberately the ONLY way a pending approval request is ever resolved
/// client-side — there is no direct "activate device" mutation anywhere
/// in the Admin UI, matching `respondToApprovalRequest`'s own role as the
/// sole entry point into the allowlisted `ACTION_HANDLERS` map.
abstract interface class ApprovalGateway {
  /// [reasonMessage] is enforced as mandatory at THIS client boundary
  /// (never an empty/whitespace-only string reaches the callable) even
  /// though the backend itself still accepts it as optional for backward
  /// compatibility with pre-existing call sites — see
  /// `remoteApproval.ts`'s own `sanitizeReasonMessage` doc comment.
  Future<void> respond({
    required String requestId,
    required bool approve,
    required String reasonMessage,
  });
}

class FirebaseApprovalGateway implements ApprovalGateway {
  const FirebaseApprovalGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw ApprovalException(
      error.code,
      error.message ?? 'İşlem tamamlanamadı.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  @override
  Future<void> respond({
    required String requestId,
    required bool approve,
    required String reasonMessage,
  }) async {
    if (reasonMessage.trim().isEmpty) {
      throw const ApprovalException(
          'invalid-argument', 'Bir gerekçe girmelisiniz.');
    }
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('respondToApprovalRequest');
    try {
      await callable.call<Map<String, dynamic>>({
        'requestId': requestId,
        'decision': approve ? 'approved' : 'rejected',
        'reasonMessage': reasonMessage.trim(),
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

class UnavailableApprovalGateway implements ApprovalGateway {
  const UnavailableApprovalGateway();

  @override
  Future<void> respond({
    required String requestId,
    required bool approve,
    required String reasonMessage,
  }) async {
    throw const ApprovalException(
        'unavailable', 'Onay backend\'i bu ortamda kullanılamıyor.');
  }
}
