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
  Future<String> ensureSignedIn() async {
    final current = fb.FirebaseAuth.instance.currentUser;
    if (current != null) return current.uid;

    final credential = await fb.FirebaseAuth.instance.signInAnonymously();
    final uid = credential.user?.uid;
    if (uid == null) {
      throw StateError(
        'Anonymous sign-in succeeded but returned no user — this should '
        'be impossible per the firebase_auth contract.',
      );
    }
    return uid;
  }
}
