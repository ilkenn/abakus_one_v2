import '../../../qr/data/technical_identity_provider.dart';
import '../../data/takeaway_guest_session_gateway.dart';
import '../../domain/models/takeaway_guest_context.dart';

/// The real, production entry point for "a scanned/opened takeaway QR
/// token becomes a [TakeawayGuestContext]" — Faz D.4. Mirrors
/// `OpenTableGuestSessionFromQrScan`'s exact reasoning.
///
/// **Identity is established before the session is opened, never after**:
/// the same uid [TechnicalIdentityProvider.ensureSignedIn] returns is
/// exactly what `openTakeawayGuestSession` will observe as
/// `request.auth.uid` server-side, so there is never a window where the
/// two could disagree.
///
/// Reuses [TechnicalIdentityProvider] as-is — channel-agnostic, no reason
/// to duplicate it for takeaway (`table_guest_session_dependencies_provider
/// .dart`'s own doc comment already establishes this precedent).
class OpenTakeawayGuestSessionFromQr {
  const OpenTakeawayGuestSessionFromQr({
    required TakeawayGuestSessionGateway gateway,
    required TechnicalIdentityProvider identityProvider,
  })  : _gateway = gateway,
        _identityProvider = identityProvider;

  final TakeawayGuestSessionGateway _gateway;
  final TechnicalIdentityProvider _identityProvider;

  /// Throws [TakeawayGuestSessionException] if [token] no longer resolves
  /// to a valid, orderable branch by the time this actually runs (a race
  /// with the caller's own earlier `resolveTakeawayQrToken` preview, or
  /// the caller skipped that preview entirely) — the caller is expected
  /// to have already shown a friendly message for the common cases via
  /// that cheaper preview call; this is the fail-closed backstop, not the
  /// primary UX path for an already-known-bad token.
  Future<TakeawayGuestContext> call(String token) async {
    final uid = await _identityProvider.ensureSignedIn();
    final opened = await _gateway.openSession(token);

    return TakeawayGuestContext(
      sessionId: opened.sessionId,
      organizationId: opened.organizationId,
      restaurantId: opened.restaurantId,
      branchId: opened.branchId,
      branchDisplayName: opened.branchDisplayName,
      expiresAt: opened.expiresAt,
      guestAuthUid: uid,
    );
  }
}
