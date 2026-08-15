import 'package:cloud_functions/cloud_functions.dart' as functions;

/// The minimized, public-safe QR preview — mirrors the Cloud Function's own
/// `TakeawayQrPublicPreview` response shape exactly (Faz D.2/D.4): no
/// `organizationId`/`restaurantId`/`branchId` ever reaches the client
/// through this call. `status` is one of `'valid'`/`'invalid'`/
/// `'expired'`/`'notFound'`, matching the callable's own values verbatim —
/// kept as a raw `String`, not a Dart enum, so this class never needs to
/// change if the server ever adds a new status the client doesn't
/// recognize yet (mirrors `TableQrPreview`'s own exact reasoning).
class TakeawayQrPreview {
  final String status;
  final String? branchDisplayName;

  const TakeawayQrPreview({
    required this.status,
    this.branchDisplayName,
  });

  /// Whether this result is safe to proceed with (attempt to open a
  /// session). Anything other than `'valid'` is a dead end the UI must
  /// show, never guess around.
  bool get isUsable => status == 'valid';
}

/// What a successful `openTakeawayGuestSession` call returns — the
/// canonical scope the server actually resolved and bound the new session
/// to. Unlike [TakeawayQrPreview], this is authenticated-only and
/// describes a session the caller now genuinely owns, so returning these
/// ids is not a data-minimization concern the way it is for the public
/// preview (mirrors `OpenedTableGuestSession`, minus `tableId`/
/// `tableDisplayName` — a takeaway QR belongs directly to a branch, not a
/// table).
class OpenedTakeawayGuestSession {
  final String sessionId;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String branchDisplayName;
  final DateTime expiresAt;

  /// `true` when this call reused an already-active session for the same
  /// (caller uid, QR token) pair rather than minting a new one — mirrors
  /// `openTakeawayGuestSession`'s own idempotent-reuse contract
  /// (`docs/decisions.md` ADR-027 Faz D.2).
  final bool reused;

  const OpenedTakeawayGuestSession({
    required this.sessionId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.branchDisplayName,
    required this.expiresAt,
    required this.reused,
  });
}

/// Thrown by [TakeawayGuestSessionGateway.openSession] for an expected,
/// non-exceptional-in-nature rejection — mirrors the Cloud Function's own
/// `HttpsError` codes (`'not-found'`/`'failed-precondition'`/
/// `'unauthenticated'`/`'invalid-argument'`) verbatim rather than
/// inventing a parallel taxonomy the caller would have to translate
/// (mirrors `TableGuestSessionException` exactly).
class TakeawayGuestSessionException implements Exception {
  final String code;
  final String message;

  const TakeawayGuestSessionException(this.code, this.message);

  @override
  String toString() => 'TakeawayGuestSessionException($code): $message';
}

/// The one client-facing boundary onto the Takeaway Guest Session backend
/// (`resolveTakeawayQrToken`/`openTakeawayGuestSession` Cloud Functions,
/// Faz D.2) — Faz D.4. Narrow, mockable interface + real implementation,
/// mirroring `TableGuestSessionGateway`'s exact shape: the real
/// `cloud_functions` SDK is unavailable under `flutter test`.
abstract interface class TakeawayGuestSessionGateway {
  Future<TakeawayQrPreview> resolveToken(String token);
  Future<OpenedTakeawayGuestSession> openSession(String token);
}

class FirebaseTakeawayGuestSessionGateway
    implements TakeawayGuestSessionGateway {
  const FirebaseTakeawayGuestSessionGateway();

  @override
  Future<TakeawayQrPreview> resolveToken(String token) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('resolveTakeawayQrToken');
    final result = await callable.call<Map<String, dynamic>>({'token': token});
    final data = result.data;
    return TakeawayQrPreview(
      status: data['status'] as String,
      branchDisplayName: data['branchDisplayName'] as String?,
    );
  }

  @override
  Future<OpenedTakeawayGuestSession> openSession(String token) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('openTakeawayGuestSession');
    try {
      final result =
          await callable.call<Map<String, dynamic>>({'token': token});
      final data = result.data;
      return OpenedTakeawayGuestSession(
        sessionId: data['sessionId'] as String,
        organizationId: data['organizationId'] as String,
        restaurantId: data['restaurantId'] as String,
        branchId: data['branchId'] as String,
        branchDisplayName: data['branchDisplayName'] as String,
        expiresAt: DateTime.parse(data['expiresAt'] as String),
        reused: data['reused'] as bool,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw TakeawayGuestSessionException(
        error.code,
        error.message ?? 'Takeaway guest session could not be opened.',
      );
    }
  }
}
