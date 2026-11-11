import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Resolves the Firebase Auth uid a Table Guest Session gets bound to —
/// Phase 3. **Never** the app's normal customer identity mechanism
/// (`AuthNotifier`/`authProvider`): a Table Guest Session's technical
/// identity is not, and must never become, a customer account. See
/// `OpenTableGuestSessionFromQrScan`'s own doc comment for why the
/// resulting `GuestSession.authenticatedUserId` stays `null` regardless
/// of which uid this returns.
abstract interface class TechnicalIdentityProvider {
  /// Returns the uid to use — reuses whoever is already signed into
  /// Firebase Auth (a real, phone-OTP-verified customer, or a previously
  /// created anonymous guest from an earlier scan this session) rather
  /// than ever creating a new anonymous user on top of an existing one.
  /// Only signs in anonymously when nobody is signed in to Firebase Auth
  /// at all.
  ///
  /// This is deliberately keyed off [fb.FirebaseAuth.instance.currentUser]
  /// directly, not `authProvider`'s own [AuthState] — `AuthNotifier`
  /// manages its state explicitly (via [SecureSessionStorage], not a live
  /// `authStateChanges()` listener), so it never reacts to this call
  /// either way; reading the real Firebase Auth SDK's current user is the
  /// one accurate signal for "would calling `signInAnonymously()` right
  /// now overwrite an existing real session," which is exactly the risk
  /// this method exists to avoid.
  Future<String> ensureSignedIn();

  /// A passive read of whoever is currently signed in — **never** triggers
  /// a sign-in, unlike [ensureSignedIn]. `null` if nobody is signed in to
  /// Firebase Auth at all. Phase 3.1: [DineInCheckoutScreen] reads this at
  /// submission time to snapshot `Order.guestAuthUid` — the exact uid the
  /// active Table Guest Session was actually opened with, without
  /// importing the raw `firebase_auth` SDK into a screen.
  String? get currentUid;
}

class FirebaseTechnicalIdentityProvider implements TechnicalIdentityProvider {
  const FirebaseTechnicalIdentityProvider();

  @override
  String? get currentUid => fb.FirebaseAuth.instance.currentUser?.uid;

  @override
  Future<String> ensureSignedIn() {
    final auth = fb.FirebaseAuth.instance;
    return ensureValidTechnicalIdentity(
      currentUser: () {
        final user = auth.currentUser;
        return user == null
            ? null
            : (uid: user.uid, isAnonymous: user.isAnonymous);
      },
      reloadCurrentUser: () async => auth.currentUser?.reload(),
      signOut: auth.signOut,
      signInAnonymously: () async {
        final credential = await auth.signInAnonymously();
        return credential.user?.uid;
      },
    );
  }
}

/// 2026-11-11 — the firebase_auth codes meaning "the cached anonymous
/// user no longer exists / its credential can't be refreshed" (e.g. the
/// backend's user was deleted). `user-disabled` is deliberately NOT here:
/// a guest disabled on purpose must not get a fresh identity automatically.
const _staleIdentityCodes = {
  'user-not-found',
  'user-token-expired',
  'invalid-user-token',
};

/// Whether [error] means the cached anonymous identity is unusable and may
/// be replaced (see [_staleIdentityCodes]).
bool isStaleTechnicalIdentityError(Object error) =>
    error is fb.FirebaseAuthException &&
    _staleIdentityCodes.contains(error.code);

/// [TechnicalIdentityProvider.ensureSignedIn]'s logic with the Firebase
/// Auth calls injected, so it is testable without a real Firebase app.
///
/// - Nobody signed in → anonymous sign-in.
/// - A real (non-anonymous) customer → reused as-is, never touched.
/// - A cached ANONYMOUS guest → checked against the backend first
///   ([reloadCurrentUser]). If the backend no longer knows it (2026-11-11:
///   the browser kept a guest the auth backend had lost, so every table
///   entry failed before reaching the server with "Masa açılırken bir
///   sorun oluştu"), it is signed out and replaced by a fresh anonymous
///   guest. Any other failure (network, disabled user) is rethrown.
Future<String> ensureValidTechnicalIdentity({
  required ({String uid, bool isAnonymous})? Function() currentUser,
  required Future<void> Function() reloadCurrentUser,
  required Future<void> Function() signOut,
  required Future<String?> Function() signInAnonymously,
}) async {
  final current = currentUser();
  if (current != null) {
    if (!current.isAnonymous) return current.uid;
    try {
      await reloadCurrentUser();
      return current.uid;
    } catch (error) {
      if (!isStaleTechnicalIdentityError(error)) rethrow;
      await signOut();
    }
  }

  final uid = await signInAnonymously();
  if (uid == null) {
    throw StateError(
      'Anonymous sign-in succeeded but returned no user — this should '
      'be impossible per the firebase_auth contract.',
    );
  }
  return uid;
}
