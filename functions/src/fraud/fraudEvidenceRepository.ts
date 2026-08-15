import type { Firestore, Transaction } from "firebase-admin/firestore";
import type {
  FraudEvidenceAccessLogEntry,
  FraudEvidenceRecord,
} from "./fraudEvidenceTypes";

/**
 * Internal Firestore access for the fraud-evidence collections — FRAUD-F.0.
 * Not exported as a Cloud Function; only `getPreciseFraudEvidence` (and,
 * later, FRAUD-F.1/F.2's own capture logic) may call these. No
 * evidence-writing helper exists yet — nothing in FRAUD-F.0 creates a
 * FraudEvidence document; that begins at FRAUD-F.1, per the approved
 * architecture's own staged-implementation-boundary decision.
 */

export const FRAUD_EVIDENCE_COLLECTION = "fraudEvidence";
export const FRAUD_EVIDENCE_ACCESS_LOG_COLLECTION = "fraudEvidenceAccessLog";

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
