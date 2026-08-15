import '../../data/table_guest_session_gateway.dart';
import '../../data/technical_identity_provider.dart';
import '../../domain/models/active_table_context.dart';
import '../../domain/models/guest_session.dart';
import '../../domain/models/table_session.dart';
import '../identity/guest_session_id_generator.dart';

/// The real, production entry point for "a scanned QR token becomes an
/// [ActiveTableContext]" — Phase 3. Replaces `QrScannerScreen`'s previous
/// use of `OpenTableSession`/`CreateGuestSession` (which wrote to
/// in-memory-only repositories) with the server-authoritative
/// `openTableGuestSession` Cloud Function. Those older classes are
/// deliberately not deleted — see this phase's report.
///
/// **Identity is established before the session is opened, never after**:
/// the same uid [TechnicalIdentityProvider.ensureSignedIn] returns is
/// exactly what `openTableGuestSession` will observe as
/// `request.auth.uid` server-side, so there is never a window where the
/// two could disagree.
///
/// **[GuestSession.authenticatedUserId] is always `null`** — a Table
/// Guest Session is never treated as a normal Abaküs customer account,
/// regardless of whether [TechnicalIdentityProvider] happened to reuse an
/// already-signed-in real customer's uid (the safe, no-session-overwrite
/// path when one exists) or created a fresh anonymous one. Boncuk/
/// loyalty/customer-profile rights are gated on `Order.customerId`/
/// `customers/{uid}`, neither of which this class or the order it later
/// produces ever touches.
class OpenTableGuestSessionFromQrScan {
  const OpenTableGuestSessionFromQrScan({
    required TableGuestSessionGateway gateway,
    required TechnicalIdentityProvider identityProvider,
    required GuestSessionIdGenerator guestSessionIdGenerator,
  })  : _gateway = gateway,
        _identityProvider = identityProvider,
        _guestSessionIdGenerator = guestSessionIdGenerator;

  final TableGuestSessionGateway _gateway;
  final TechnicalIdentityProvider _identityProvider;
  final GuestSessionIdGenerator _guestSessionIdGenerator;

  /// Throws [TableGuestSessionException] if [token] no longer resolves to
  /// a valid, orderable table by the time this actually runs (a race with
  /// the caller's own earlier `resolveTableQrToken` preview, or the
  /// caller skipped that preview entirely) — the caller is expected to
  /// have already shown a friendly message for the common cases via that
  /// cheaper preview call; this is the fail-closed backstop, not the
  /// primary UX path for an already-known-bad token.
  Future<ActiveTableContext> call(String token) async {
    await _identityProvider.ensureSignedIn();
    final opened = await _gateway.openSession(token);

    final now = DateTime.now();
    final session = TableSession(
      id: opened.sessionId,
      restaurantId: opened.restaurantId,
      branchId: opened.branchId,
      tableId: opened.tableId,
      status: TableSessionStatus.active,
      openedAt: now,
      guestSessionIds: const [],
      activeOrderIds: const [],
    );
    final guestSession = GuestSession(
      id: _guestSessionIdGenerator.nextGuestSessionId(),
      tableSessionId: opened.sessionId,
      branchId: opened.branchId,
      tableId: opened.tableId,
      detectedLanguageCode: 'tr',
      selectedLanguageCode: 'tr',
      authenticatedUserId: null,
      createdAt: now,
      lastSeenAt: now,
      status: GuestSessionStatus.active,
    );

    return ActiveTableContext(
      restaurantId: opened.restaurantId,
      branchId: opened.branchId,
      branchName: opened.branchDisplayName,
      tableId: opened.tableId,
      tableName: opened.tableDisplayName,
      session: session,
      guestSession: guestSession,
      reservationContextId: opened.reservationContextId,
    );
  }
}
