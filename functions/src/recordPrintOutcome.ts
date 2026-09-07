import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";

/**
 * `recordPrintOutcome` — AP-5 Sprint 4.
 *
 * The `RecordPrintOutcome` command the canonical architecture doc's §9/§14
 * target design names — exposed as its own callable (distinct from
 * `requestPrintJob`'s internal use of the same transition) for a manual
 * "staff confirms the ticket printed by other means" fallback after a
 * mock/real transport reports `failed`, and as the seam a future real
 * printer worker would call instead of `requestPrintJob`'s own inline mock
 * -transport step, with no caller-facing shape change.
 *
 * Never overwrites a job that already succeeded — once a print job is
 * `success`, that is genuinely terminal (a stray later call must never
 * demote a proven-good print back to `failed`). `failed` is deliberately
 * NOT treated as terminal here: it is exactly the state this callable's
 * own manual-override fallback exists to move on from (a job stuck
 * `failed` from the mock/real transport can always be confirmed `success`
 * by staff, or re-recorded `failed` again, idempotently either way).
 */

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return raw;
}

export const recordPrintOutcome = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const printJobId = requireString(data.printJobId, "printJobId");
    const outcome = data.outcome;
    if (outcome !== "success" && outcome !== "failed") {
      throw new HttpsError("invalid-argument", "outcome must be 'success' or 'failed'.");
    }

    const db = getFirestore();
    const ref = db.collection("printJobs").doc(printJobId);

    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Print job not found.");
      }
      const job = snap.data()!;
      requireStaffPermission(request, job.organizationId as string, "manageKitchenOperations");
      requireBranchAccess(request, job.organizationId as string, job.branchId as string);

      if (job.status === "success") {
        return { printJobId, status: job.status as string };
      }

      tx.update(ref, { status: outcome, updatedAt: Timestamp.now() });
      return { printJobId, status: outcome };
    });
  },
);
