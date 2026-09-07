import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { derivePrintJobId, processPrintJob } from "./printJobEngine";

/**
 * `requestPrintJob` — AP-5 Sprint 4.
 *
 * The manual "Fiş Yazdır / Tekrar Yazdır" trigger from a kitchen card. The
 * AUTOMATIC print job opened at order acceptance goes through
 * `preparePrintJobForAcceptance`/`applyPrintJobPlan` inline inside the
 * acceptance transaction itself (`acceptOrderLine.ts`'s four real call
 * sites) — this callable is never that path.
 *
 * Reuses the existing `manageKitchenOperations` staff-tier permission
 * (already correctly tiered across `staff`/`manager`/`admin`/`tenantOwner`
 * — printing a kitchen ticket is exactly the same class of routine,
 * front-line kitchen action as advancing a work item's status, not a new
 * authorization decision).
 *
 * `isCopy: false` (default) opens the same deterministic generation-0 job
 * the acceptance path would — calling this before or after acceptance ran
 * is idempotent with it (whichever write lands first wins; the other is a
 * no-op that returns the existing job's own current status, never
 * re-driving an already-terminal job through the mock transport again).
 * `isCopy: true` (every real KDS-card reprint) always mints a brand-new
 * job at the next generation number — a reprint is never confused with
 * the original in the data, mirroring `KitchenTicket.isCopy`/
 * `KitchenPrintAttempt.isRetry`'s own "always distinct, never mutated in
 * place" precedent.
 */

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return raw;
}

export const requestPrintJob = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");
    const orderId = requireString(data.orderId, "orderId");
    const stationId = requireString(data.stationId, "stationId");
    const isCopy = data.isCopy === true;

    requireStaffPermission(request, organizationId, "manageKitchenOperations");
    requireBranchAccess(request, organizationId, branchId);

    const db = getFirestore();
    const now = Timestamp.now();
    const uid = request.auth.uid;

    const { printJobId, created, existingStatus } = await db.runTransaction(async (tx) => {
      if (!isCopy) {
        const ref = db.collection("printJobs").doc(derivePrintJobId(orderId, stationId, 0));
        const snap = await tx.get(ref);
        if (snap.exists) {
          return {
            printJobId: ref.id,
            created: false,
            existingStatus: snap.data()!.status as string,
          };
        }
        tx.set(ref, {
          organizationId,
          branchId,
          orderId,
          stationId,
          status: "pending",
          retryCount: 0,
          backupPrinterId: null,
          isCopy: false,
          requestedByUid: uid,
          requestedAt: now,
          updatedAt: now,
        });
        return { printJobId: ref.id, created: true, existingStatus: null };
      }

      // Reprint: always a new job, at the next generation for this
      // (order, station) pair. Single-field `orderId` query + in-memory
      // `stationId` filter — same no-composite-index reasoning as
      // `resolveMockPrintOutcome`.
      const existingSnap = await tx.get(db.collection("printJobs").where("orderId", "==", orderId));
      const generation = existingSnap.docs.filter((doc) => doc.data().stationId === stationId).length;
      const ref = db.collection("printJobs").doc(derivePrintJobId(orderId, stationId, generation));
      tx.set(ref, {
        organizationId,
        branchId,
        orderId,
        stationId,
        status: "pending",
        retryCount: 0,
        backupPrinterId: null,
        isCopy: true,
        requestedByUid: uid,
        requestedAt: now,
        updatedAt: now,
      });
      return { printJobId: ref.id, created: true, existingStatus: null };
    });

    if (!created) {
      return { printJobId, status: existingStatus };
    }

    const status = await processPrintJob(db, printJobId, branchId, stationId);
    return { printJobId, status };
  },
);
