/**
 * Server-side retention configuration for FraudEvidence — FRAUD-F.0.
 * Mirrors lib/core/fraud/domain/fraud_evidence_retention_policy.dart.
 * TTL-ready: computeExpiresAt is the one place a FraudEvidence.expiresAt
 * value is derived from.
 *
 * The exact production retention duration is a legal/KVKK release-gate
 * decision, not an engineering one (approved architecture §10) — nothing
 * here hardcodes a production default; retentionDurationMs must always be
 * supplied explicitly, from deployment configuration once one exists
 * (mirroring appCheckConfig.ts's ENFORCE_APP_CHECK discipline). No
 * scheduled delete sweep is implemented — Firestore TTL (configured on
 * the `expiresAt` field via Firestore's own TTL policy mechanism,
 * console/gcloud, not application code) is the intended primary deletion
 * mechanism, per the approved architecture's explicit instruction not to
 * build a sweep unless proven required.
 */
export interface FraudEvidenceRetentionPolicy {
  id: string;
  retentionDurationMs: number;
  legalBasisVersion?: string | null;
}

export function computeExpiresAt(
  policy: FraudEvidenceRetentionPolicy,
  from: Date,
): Date {
  return new Date(from.getTime() + policy.retentionDurationMs);
}

/**
 * Non-production, deterministic-for-tests policy only — never referenced
 * by any production code path. Exists so FRAUD-F.0's own tests have a
 * concrete, clearly-labeled duration to assert against without inventing
 * a production number.
 */
export const TEST_ONLY_RETENTION_POLICY: FraudEvidenceRetentionPolicy = {
  id: "test-only-do-not-use-in-production",
  retentionDurationMs: 24 * 60 * 60 * 1000, // 24h — arbitrary, test-only.
  legalBasisVersion: null,
};
