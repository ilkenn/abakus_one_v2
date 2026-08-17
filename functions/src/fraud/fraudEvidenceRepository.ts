import type { Firestore, Transaction } from "firebase-admin/firestore";
import type {
  FraudEvidenceAccessLogEntry,
  FraudEvidenceRecord,
} from "./fraudEvidenceTypes";

/**
 * Internal Firestore access for the fraud-evidence collections —
 * FRAUD-F.0/F.1. Not exported as a Cloud Function; only
 * `getPreciseFraudEvidence` and `saveDeliveryAddress` (and, later,
 * FRAUD-F.2's own capture logic) may call these.
 */

export const FRAUD_EVIDENCE_COLLECTION = "fraudEvidence";
export const FRAUD_EVIDENCE_ACCESS_LOG_COLLECTION = "fraudEvidenceAccessLog";

/**
 * FRAUD-F.1 records raw signals only — no risk-scoring policy exists yet
 * (approved architecture §9/§10: "no permanent thresholds in this phase").
 * This constant names that honestly rather than leaving `policyVersion`
 * `null`, so a future real policy version is unambiguously distinguishable
 * from "no policy was ever active" in historical records.
 */
export const FRAUD_F1_POLICY_VERSION = "fraud-f1-signals-only-no-risk-policy";

/** Same discipline as FRAUD_F1_POLICY_VERSION — FRAUD-F.2 also defines no real risk policy yet. */
export const FRAUD_F2_POLICY_VERSION = "fraud-f2-signals-only-no-risk-policy";

export async function getFraudEvidenceInTransaction(
  tx: Transaction,
  db: Firestore,
  evidenceId: string,
): Promise<FraudEvidenceRecord | null> {
  const ref = db.collection(FRAUD_EVIDENCE_COLLECTION).doc(evidenceId);
  const snapshot = await tx.get(ref);
  if (!snapshot.exists) return null;
  return snapshot.data() as FraudEvidenceRecord;
}

/**
 * Writes exactly one immutable access-log entry inside the caller's own
 * transaction — never a standalone write, so it always commits atomically
 * with (and only with) the read it documents.
 */
export function writeAccessLogEntryInTransaction(
  tx: Transaction,
  db: Firestore,
  entry: FraudEvidenceAccessLogEntry,
): void {
  const ref = db
    .collection(FRAUD_EVIDENCE_ACCESS_LOG_COLLECTION)
    .doc(entry.id);
  tx.set(ref, entry);
}

/**
 * Creates a new, immutable `fraudEvidence` document inside the caller's own
 * transaction — FRAUD-F.1's first real writer. Returns the generated
 * Firestore-auto-id doc reference so the caller can record it (e.g. as
 * `SavedAddress`'s own audit trail) without a second round trip. The
 * caller is responsible for having already fully resolved every field on
 * `record` (this function performs no validation/derivation of its own —
 * see `deviceLocationCandidate.ts`/`geoDistance.ts` for that).
 */
export function createFraudEvidenceInTransaction(
  tx: Transaction,
  db: Firestore,
  record: Omit<FraudEvidenceRecord, "id">,
): string {
  const ref = db.collection(FRAUD_EVIDENCE_COLLECTION).doc();
  tx.set(ref, { ...record, id: ref.id });
  return ref.id;
}
