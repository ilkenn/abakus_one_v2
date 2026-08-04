/// Verifies that a webhook delivery's signature was actually produced
/// by the holder of a given secret — Phase 8 (`docs/decisions.md`
/// ADR-025). Mirrors this codebase's established provider-adapter
/// template (abstract interface + one safe default with no real
/// implementation) — see [UnverifiedWebhookSignatureVerifier].
abstract interface class WebhookSignatureVerifier {
  bool verify({
    required String payload,
    required String signature,
    required String secret,
  });
}

/// The only implementation in this codebase — **always returns
/// `false`, fail-closed**. Real HMAC-based signature verification
/// (the scheme essentially every provider uses) needs a cryptographic
/// hashing primitive this codebase does not currently have as a
/// dependency (no `crypto` package, no equivalent in `dart:core`/
/// `dart:convert`) — adding one is a new-dependency decision requiring
/// explicit approval (`CLAUDE.md` §15), not something to add silently
/// while building a foundation. Until that decision is made and a real
/// verifier exists, treating every delivery as unverified is the only
/// safe default — the alternative (an implementation that always
/// returns `true`) would be exactly the unsafe "looks like security but
/// isn't" default this codebase's authorization policies already
/// explicitly refuse to have (`PosAuthorizationPolicy`'s own doc
/// comment, `docs/decisions.md` ADR-012).
class UnverifiedWebhookSignatureVerifier implements WebhookSignatureVerifier {
  const UnverifiedWebhookSignatureVerifier();

  @override
  bool verify({
    required String payload,
    required String signature,
    required String secret,
  }) =>
      false;
}
