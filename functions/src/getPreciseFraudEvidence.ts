import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { randomUUID } from "node:crypto";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requirePlatformCapability } from "./platformCapabilities";
import {
  getFraudEvidenceInTransaction,
  writeAccessLogEntryInTransaction,
} from "./fraud/fraudEvidenceRepository";
import type { FraudEvidenceRecord } from "./fraud/fraudEvidenceTypes";

/**
 * The ONLY precise human evidence-access endpoint — FRAUD-F.0
 * (docs/decisions.md §7 of the approved architecture). No Firestore Rule
 * grants any human client (including platformOwner) direct read access to
 * `fraudEvidence` — see firestore.rules — so this callable is the sole
 * path, and every access it grants is unconditionally logged before data
 * is returned.
 *
 * Required sequence, exactly as approved:
 *  1. authenticate caller
 *  2. resolve authorization from server-trusted identity/claims and
 *     require the `fraudEvidence.readPrecise` CAPABILITY
 *     (`requirePlatformCapability` — `platformCapabilities.ts`). This
 *     callable never checks a `platformRole` literal itself — it depends
 *     only on the capability boundary, so granting the same capability to
 *     a future dedicated identity never requires touching this file.
 *  3. enter a single Firestore transaction (`{ maxAttempts: 1 }` — no
 *     silent retry of application logic; only genuine contention would
 *     ever retry, and this endpoint has none to contend over)
 *  4. read the requested evidence
 *  5. enforce the resource/context boundary (evidence must exist)
 *  6. write an immutable fraudEvidenceAccessLog entry
 *  7. only if the transaction commits successfully...
 *  8. ...return the precise evidence
 *
 * If evidence does not exist, the transaction throws `not-found` before
 * ever reaching the audit-log write — an access *attempt* against a
 * nonexistent id is not itself logged, matching the literal approved
 * sequence (audit logging happens only once the resource/context boundary
 * check has something real to bound). If the audit-log write itself fails
 * for any reason, the whole transaction rejects and this callable throws
 * — there is no code path that can return evidence without a committed
 * audit entry, because both happen inside one atomic transaction and the
 * HTTP response is only constructed after `runTransaction` resolves.
 *
 * App Check: this callable never reads any App-Check-shaped field from
 * `request.data` — enforcement is entirely `enforceAppCheck`'s own,
 * Firebase-verified mechanism (`request.app`), never a client-asserted
 * value (docs/decisions.md FRAUD-F.0 §8).
 */

interface GetPreciseFraudEvidenceResult {
  evidence: FraudEvidenceRecord;
}

export const getPreciseFraudEvidence = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (
    request: CallableRequest,
  ): Promise<GetPreciseFraudEvidenceResult> => {
    requirePlatformCapability(request, "fraudEvidence.readPrecise");
    const actorUid = request.auth!.uid;

    const evidenceId = request.data?.evidenceId;
    if (typeof evidenceId !== "string" || evidenceId.length === 0) {
      throw new HttpsError("invalid-argument", "evidenceId is required.");
    }

    const db = getFirestore();
    const now = new Date().toISOString();

    const evidence = await db.runTransaction(
      async (tx) => {
        const record = await getFraudEvidenceInTransaction(
          tx,
          db,
          evidenceId,
        );
        if (!record) {
          throw new HttpsError("not-found", "No such evidence record.");
        }

        writeAccessLogEntryInTransaction(tx, db, {
          id: randomUUID(),
          evidenceId: record.id,
          actorUid,
          capability: "fraudEvidence.readPrecise",
          action: "read",
          accessedAt: now,
          scope: {
            organizationId: record.organizationId,
            branchId: record.branchId,
            orderId: record.orderId,
          },
        });

        return record;
      },
      { maxAttempts: 1 },
    );

    return { evidence };
  },
);
