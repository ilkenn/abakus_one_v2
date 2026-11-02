import 'identity_toolkit_rest_auth_client.dart';

/// 2026-10-30 — the Windows REST-sign-in bridge's own session holder.
///
/// A deliberate, narrow exception to "never use a global mutable
/// variable": this exists for the exact same reason `fb.FirebaseAuth
/// .instance` itself is a global singleton this whole app already depends
/// on everywhere — it stands in for that same role on Windows, for the one
/// case (`RestEmailPasswordAuthClient`) where the real native singleton's
/// own session state can never be populated (no public API accepts a
/// REST-obtained token pair). Every reader of this class
/// (`RestCallableClient`, `DefaultStaffClaimsSyncClient`) only ever
/// consults it as a *fallback* after checking the real
/// `FirebaseAuth.instance.currentUser` first — on every platform other
/// than Windows, and even on Windows whenever the native sign-in this
/// class's own doc comment describes firing in the background eventually
/// succeeds, this class is simply never consulted.
///
/// Holds at most one session (this app signs in one staff user at a time
/// on one desktop terminal) — `set`/`clear` replace it wholesale, never
/// merge.
abstract final class WindowsRestAuthSession {
  WindowsRestAuthSession._();

  static RestAuthTokens? _tokens;

  /// How long before [RestAuthTokens.expiresAt] a cached token is treated
  /// as already-expired — refreshes proactively rather than racing a call
  /// that might land exactly as the real server-side expiry hits.
  static const _expiryBuffer = Duration(seconds: 60);

  static bool get isActive => _tokens != null;

  static String? get uid => _tokens?.localId;

  static void set(RestAuthTokens tokens) => _tokens = tokens;

  static void clear() => _tokens = null;

  /// The current, valid [RestAuthTokens.idToken] — transparently refreshed
  /// via [client] first if the cached one is at/past [_expiryBuffer] of its
  /// own expiry. `null` if no session is active, or if a refresh attempt
  /// fails (the stale token is discarded rather than returned, since
  /// Identity Toolkit would reject it anyway — the caller sees "no token"
  /// and surfaces its own real error instead of a misleading downstream
  /// 401).
  static Future<String?> currentIdToken({
    required IdentityToolkitRestAuthClient client,
  }) async {
    final tokens = _tokens;
    if (tokens == null) return null;
    if (DateTime.now().isBefore(tokens.expiresAt.subtract(_expiryBuffer))) {
      return tokens.idToken;
    }
    try {
      final refreshed = await client.refresh(tokens.refreshToken);
      _tokens = refreshed;
      return refreshed.idToken;
    } on IdentityToolkitAuthException {
      _tokens = null;
      return null;
    }
  }

  /// Forces a refresh regardless of [RestAuthTokens.expiresAt] — the REST
  /// equivalent of `getIdTokenResult(true)`'s force-refresh flag, used by
  /// `StaffClaimsSyncClient.syncAndRefresh`'s periodic
  /// (non-fresh-sign-in) `refreshSession` path, where the whole point is
  /// detecting a role revoked since the cached token was minted — a
  /// not-yet-expired cached token must never be trusted there. `null` if
  /// no session is active or the refresh itself fails (session treated as
  /// ended, same reasoning as [currentIdToken]).
  static Future<String?> forceRefresh({
    required IdentityToolkitRestAuthClient client,
  }) async {
    final tokens = _tokens;
    if (tokens == null) return null;
    try {
      final refreshed = await client.refresh(tokens.refreshToken);
      _tokens = refreshed;
      return refreshed.idToken;
    } on IdentityToolkitAuthException {
      _tokens = null;
      return null;
    }
  }
}
