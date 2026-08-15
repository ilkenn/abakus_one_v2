import 'package:shared_preferences/shared_preferences.dart';

/// Persists the one opaque `submissionKey` string a Gel Al QR guest
/// checkout is currently using, keyed by the guest session id — Faz D.4
/// §12 (idempotency across a browser refresh). Mirrors
/// `HeroAbacusScenarioStore`'s exact shape: interface + real
/// `shared_preferences`-backed implementation + fail-safe on any error
/// (a storage failure degrades to "generate a fresh key," never a crash).
///
/// **Deliberately minimal, not a general checkout-state persistence
/// system**: only the idempotency key itself survives a refresh, not the
/// cart contents or the contact form fields — those still reset (a
/// genuinely new, larger feature, out of this phase's scope). What this
/// narrow mechanism actually buys: if a customer's browser reloads mid-
/// checkout (accidental refresh, a flaky mobile connection) and they then
/// re-fill the same order and submit again, the retry reuses the same
/// `submissionKey` the backend already saw — recognized as a genuine
/// idempotent retry (`docs/decisions.md` ADR-027 Faz D.3's own
/// `sha256(uid|submissionKey)` contract) rather than silently creating a
/// second real order.
abstract interface class TakeawayGuestSubmissionKeyStore {
  Future<String?> readPendingKey(String sessionId);
  Future<void> persistPendingKey(String sessionId, String submissionKey);

  /// Called once a submission actually succeeds (including a
  /// backend-recognized duplicate) — there is no longer a "pending"
  /// submission to protect against a future refresh.
  Future<void> clearPendingKey(String sessionId);
}

class SharedPreferencesTakeawayGuestSubmissionKeyStore
    implements TakeawayGuestSubmissionKeyStore {
  static const _keyPrefix = 'takeawayGuestPendingSubmissionKey_';

  const SharedPreferencesTakeawayGuestSubmissionKeyStore();

  @override
  Future<String?> readPendingKey(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_keyPrefix$sessionId');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> persistPendingKey(String sessionId, String submissionKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$sessionId', submissionKey);
    } catch (_) {
      // Best-effort: worst case, a refresh mid-checkout generates a fresh
      // key instead of reusing the pending one — still safe (the backend's
      // own idempotency is scoped per-key, never per-cart-contents), just
      // not refresh-resilient for that one attempt.
    }
  }

  @override
  Future<void> clearPendingKey(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$sessionId');
    } catch (_) {
      // Best-effort — a leftover key only ever causes an old, already-
      // resolved key to be reused on some future unrelated checkout for
      // the same session id, which is still safe (idempotent), just
      // slightly wasteful.
    }
  }
}
