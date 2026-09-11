import 'package:cloud_functions/cloud_functions.dart' as functions;

/// Dine-in Sprint 3 — mirrors `functions/src/serviceRequests.ts`'s
/// `ServiceRequestType` verbatim.
enum ServiceRequestType { callWaiter, requestBill }

extension ServiceRequestTypeWire on ServiceRequestType {
  String toWire() => switch (this) {
        ServiceRequestType.callWaiter => 'callWaiter',
        ServiceRequestType.requestBill => 'requestBill',
      };
}

/// The minimized, public-safe QR preview — mirrors the Cloud Function's
/// own `TableQrPublicPreview` response shape exactly (Table Guest Session
/// Phase 1/2 review fix): no `organizationId`/`restaurantId`/`branchId`/
/// `tableId` ever reaches the client through this call. `status` is one
/// of `'valid'`/`'invalid'`/`'expired'`/`'notFound'`/`'reserved'` (the last
/// added Faz R.1C.2 — a table currently protected by an active
/// reservation's T-20 window), matching the callable's own values verbatim
/// (kept as a raw `String`, not a Dart enum, so this class never needs to
/// change if the server ever adds a new status the client doesn't
/// recognize yet — an unrecognized value simply isn't `'valid'`,
/// [isUsable] fails closed either way).
class TableQrPreview {
  final String status;
  final String? tableDisplayName;
  final String? branchDisplayName;

  const TableQrPreview({
    required this.status,
    this.tableDisplayName,
    this.branchDisplayName,
  });

  /// Whether this result is safe to proceed with (attempt to open a
  /// session). Anything other than `'valid'` is a dead end the UI must
  /// show, never guess around.
  bool get isUsable => status == 'valid';
}

/// What a successful `openTableGuestSession` call returns — the canonical
/// scope the server actually resolved and bound the new session to
/// (unlike [TableQrPreview], this is authenticated-only and describes a
/// session the caller now genuinely owns, so returning these ids is not a
/// data-minimization concern the way it is for the public preview).
class OpenedTableGuestSession {
  final String sessionId;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String tableId;
  final String tableDisplayName;
  final String branchDisplayName;
  final DateTime expiresAt;

  /// Server-generated, immutable snapshot (Faz R.1C.2 §11/§13) — `null`
  /// for the ordinary walk-in case, or the reservationId of the
  /// `activeReservationTableContext` that was live on this table at the
  /// moment the session was opened. Never client-supplied, never
  /// re-derived later — carried forward as-is everywhere this session's
  /// identity flows (an order it places, in particular).
  final String? reservationContextId;

  const OpenedTableGuestSession({
    required this.sessionId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.tableId,
    required this.tableDisplayName,
    required this.branchDisplayName,
    required this.expiresAt,
    this.reservationContextId,
  });
}

/// Thrown by [TableGuestSessionGateway.openSession] for an expected,
/// non-exceptional-in-nature rejection — mirrors the Cloud Function's own
/// `HttpsError` codes (`'not-found'`/`'failed-precondition'`/
/// `'unauthenticated'`/`'invalid-argument'`) verbatim rather than
/// inventing a parallel taxonomy the caller would have to translate.
class TableGuestSessionException implements Exception {
  final String code;
  final String message;

  const TableGuestSessionException(this.code, this.message);

  @override
  String toString() => 'TableGuestSessionException($code): $message';
}

/// The one client-facing boundary onto the Table Guest Session backend
/// (`resolveTableQrToken`/`openTableGuestSession` Cloud Functions) — Phase
/// 3. Narrow, mockable interface + real implementation, mirroring
/// `EmailPasswordAuthClient`/`OrderFirestoreClient`'s exact reasoning: the
/// real `cloud_functions` SDK is unavailable under `flutter test`.
abstract interface class TableGuestSessionGateway {
  Future<TableQrPreview> resolveToken(String token);
  Future<OpenedTableGuestSession> openSession(String token);

  /// Dine-in Sprint 3 — a guest-triggered waiter call / bill request.
  /// [guestSessionId] is the real `tableGuestSessions` document id (i.e.
  /// [ActiveTableContext.session]'s `id`, which is `opened.sessionId` —
  /// `ActiveTableContext.guestSession.id` is a LOCAL-only sequential id,
  /// never this document id, and must never be sent here).
  Future<void> createServiceRequest({
    required String guestSessionId,
    required ServiceRequestType type,
  });
}

class FirebaseTableGuestSessionGateway implements TableGuestSessionGateway {
  const FirebaseTableGuestSessionGateway();

  @override
  Future<TableQrPreview> resolveToken(String token) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('resolveTableQrToken');
    final result = await callable.call<Map<String, dynamic>>({'token': token});
    final data = result.data;
    return TableQrPreview(
      status: data['status'] as String,
      tableDisplayName: data['tableDisplayName'] as String?,
      branchDisplayName: data['branchDisplayName'] as String?,
    );
  }

  @override
  Future<OpenedTableGuestSession> openSession(String token) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('openTableGuestSession');
    try {
      final result =
          await callable.call<Map<String, dynamic>>({'token': token});
      final data = result.data;
      return OpenedTableGuestSession(
        sessionId: data['sessionId'] as String,
        organizationId: data['organizationId'] as String,
        restaurantId: data['restaurantId'] as String,
        branchId: data['branchId'] as String,
        tableId: data['tableId'] as String,
        tableDisplayName: data['tableDisplayName'] as String,
        branchDisplayName: data['branchDisplayName'] as String,
        expiresAt: DateTime.parse(data['expiresAt'] as String),
        reservationContextId: data['reservationContextId'] as String?,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw TableGuestSessionException(
        error.code,
        error.message ?? 'Table guest session could not be opened.',
      );
    }
  }

  @override
  Future<void> createServiceRequest({
    required String guestSessionId,
    required ServiceRequestType type,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('createServiceRequest');
    try {
      await callable.call<Map<String, dynamic>>({
        'guestSessionId': guestSessionId,
        'type': type.toWire(),
      });
    } on functions.FirebaseFunctionsException catch (error) {
      throw TableGuestSessionException(
        error.code,
        error.message ?? 'İstek gönderilemedi.',
      );
    }
  }
}
