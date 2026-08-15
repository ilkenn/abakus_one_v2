/// Server-side retention configuration for `FraudEvidence` — FRAUD-F.0.
/// TTL-ready: [computeExpiresAt] is the one place a `FraudEvidence.expiresAt`
/// value is derived from, so a future production retention-duration change
/// never requires touching evidence-creation call sites — only this
/// policy's own configured [retentionDuration].
///
/// **The exact production retention duration is a legal/KVKK release-gate
/// decision, not an engineering one** (the approved architecture's §10) —
/// nothing in this class hardcodes a production default. [retentionDuration]
/// must always be supplied explicitly by the caller from deployment
/// configuration, mirroring `functions/src/appCheckConfig.ts`'s
/// `ENFORCE_APP_CHECK`'s own "deployment config, never hardcoded" rule. A
/// short, explicitly-test-only duration is expected in test code (see
/// `test/core/fraud/domain/fraud_evidence_retention_policy_test.dart`) —
/// never presented as a production value.
class FraudEvidenceRetentionPolicy {
  const FraudEvidenceRetentionPolicy({
    required this.id,
    required this.retentionDuration,
    this.legalBasisVersion,
  });

  final String id;
  final Duration retentionDuration;

  /// `null` until a real KVKK-approved legal basis exists for this policy.
  final String? legalBasisVersion;

  DateTime computeExpiresAt(DateTime from) => from.add(retentionDuration);
}
