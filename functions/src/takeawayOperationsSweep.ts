import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";
import { prepareKitchenWorkAndStockConsumption, applyKitchenWorkAndStockConsumption } from "./acceptOrderLine";
import { preparePrintJobForAcceptance, applyPrintJobPlan } from "./printJobEngine";
import { applyTakeawayLifecycleTransition, writeTakeawayOrderStatusChangeAuditEvent } from "./takeawayOrderLifecycle";

/**
 * AP-6 Sprint 1 — the takeaway analogue of `reservationSweep.ts`, mirroring
 * its exact discipline: every due document gets its own small transaction,
 * re-validating its own precondition inside that transaction
 * (idempotent/retry-safe against a concurrent sweep run or a manual staff
 * action in between the query and the transaction), and one failing
 * candidate (`try`/`catch`, mirrors `runPreorderKdsReleaseSweep`) can never
 * abort the rest of the batch.
 *
 * Two independent concerns, bundled into one scheduled function rather than
 * two (same reasoning `reservationSweep.ts` gives for its own two concerns —
 * only one Cloud Scheduler job provisioned):
 *
 * 1. **Branch settings auto-revert**: a `branchTakeawaySettings` document
 *    still `paused` past its own `pausedUntil` reverts to `active`. `busy`
 *    mode has no duration field to expire on this sprint — the UI's own
 *    `busyDelayMinutes` picker never asks staff to CHOOSE how long busy
 *    mode lasts, only how much extra delay to add per order, so there is no
 *    client-supplied instant to sweep on; staff switches back to `active`
 *    manually, the same way they already switch mode.
 * 2. **Scheduled order promotion**: an order still `scheduled` past its own
 *    `scheduledFor` is promoted to `confirmed`, reusing
 *    `prepareKitchenWorkAndStockConsumption`/`applyKitchenWorkAndStockConsumption`
 *    and `preparePrintJobForAcceptance`/`applyPrintJobPlan` VERBATIM — the
 *    exact same primitives `respondToTakeawayOrder.ts`'s manual `confirm`
 *    path already uses, never a second, parallel acceptance path that could
 *    drift from it.
 */

const SETTINGS_REVERT_BATCH_SIZE = 50;
const ORDER_PROMOTION_BATCH_SIZE = 50;

/** Internal system-actor identity for writes this sweep performs — never a real staff uid. */
const SWEEP_SYSTEM_ACTOR = "system:takeawayOperationsSweep";

/**
 * Reverts every `branchTakeawaySettings` document still `paused` past its
 * own `pausedUntil` back to `active`. Returns the number of settings
 * documents actually reverted by this call (not merely queried — one
 * already reverted or re-toggled by staff in between is skipped, not
 * counted).
 */
export async function runBranchTakeawaySettingsRevertSweep(
  db: Firestore,
  now: Date,
): Promise<number> {
  const nowTimestamp = Timestamp.fromDate(now);
  const dueSnapshot = await db
    .collection("branchTakeawaySettings")
    .where("status", "==", "paused")
    .where("pausedUntil", "<=", nowTimestamp)
    .limit(SETTINGS_REVERT_BATCH_SIZE)
    .get();

  let processed = 0;
  for (const snapshot of dueSnapshot.docs) {
    const settingsRef = snapshot.ref;
    try {
      const reverted = await db.runTransaction(async (tx) => {
        const doc = await tx.get(settingsRef);
        if (!doc.exists) return false;
        const settings = doc.data()!;
        // Idempotent/retry-safe re-check — another sweep invocation or a
        // staff action (a fresh `updateTakeawayOperationStatus` call) may
        // have already changed this document between the query and here.
        if (settings.status !== "paused") return false;
        const pausedUntil = settings.pausedUntil;
        const pausedUntilMs =
          typeof pausedUntil?.toMillis === "function" ? pausedUntil.toMillis() : null;
        if (pausedUntilMs === null || pausedUntilMs > now.getTime()) return false;

        tx.set(
          settingsRef,
          {
            status: "active",
            busyDelayMinutes: 0,
            pausedUntil: null,
            updatedByStaffId: SWEEP_SYSTEM_ACTOR,
            updatedAt: nowTimestamp,
            revision: (Number(settings.revision) || 1) + 1,
          },
          { merge: false },
        );
        return true;
      });
      if (reverted) processed += 1;
    } catch (error) {
      console.error(`takeawayOperationsSweep: failed reverting ${settingsRef.id}`, error);
    }
  }
  return processed;
}

/**
 * Promotes every `orders` document still `scheduled` past its own
 * `scheduledForTimestamp` to `confirmed`, enqueueing real kitchen work and
 * a print job exactly as a staff `confirm` would. Returns the number of
 * orders actually promoted by this call (not merely queried).
 */
export async function runScheduledOrderPromotionSweep(
  db: Firestore,
  now: Date,
): Promise<number> {
  const nowTimestamp = Timestamp.fromDate(now);
  const dueSnapshot = await db
    .collection("orders")
    .where("status", "==", "scheduled")
    .where("scheduledForTimestamp", "<=", nowTimestamp)
    .orderBy("scheduledForTimestamp", "asc")
    .limit(ORDER_PROMOTION_BATCH_SIZE)
    .get();

  let processed = 0;
  for (const snapshot of dueSnapshot.docs) {
    const orderRef = snapshot.ref;
    const orderId = orderRef.id;
    try {
      const promoted = await db.runTransaction(async (tx) => {
        const orderDoc = await tx.get(orderRef);
        if (!orderDoc.exists) return false;
        const order = orderDoc.data()!;
        // Idempotent/retry-safe re-check — a concurrent sweep run or a
        // manual staff cancel/reject in between the query and here.
        if (order.status !== "scheduled") return false;
        const scheduledForTimestamp = order.scheduledForTimestamp;
        const scheduledForMs =
          typeof scheduledForTimestamp?.toMillis === "function"
            ? scheduledForTimestamp.toMillis()
            : null;
        if (scheduledForMs === null || scheduledForMs > now.getTime()) return false;

        const organizationId = order.organizationId as string;
        const branchId = order.branchId as string;

        // Read phase — must complete before this transaction's first write
        // below (same discipline `respondToTakeawayOrder.ts` follows for
        // this exact pair of calls).
        const acceptedLines = (Array.isArray(order.lines) ? order.lines : []).map(
          (line: Record<string, unknown>, index: number) => ({
            orderLineId: `kt-${orderId}-line-${index}`,
            productId: line.productId as string,
            quantity: line.quantity as number,
          }),
        );
        const stockPlan = await prepareKitchenWorkAndStockConsumption({
          tx,
          db,
          organizationId,
          branchId,
          orderId,
          channel: order.channel as string,
          acceptedLines,
          performedByUid: SWEEP_SYSTEM_ACTOR,
          now: nowTimestamp,
        });
        const printPlan = await preparePrintJobForAcceptance({
          tx,
          db,
          organizationId,
          branchId,
          orderId,
          stationId: "shared",
          now: nowTimestamp,
        });

        applyTakeawayLifecycleTransition({
          tx,
          orderRef,
          orderId,
          order,
          fromStatus: "scheduled",
          toStatus: "confirmed",
          actorType: "system",
          now: nowTimestamp,
        });
        writeTakeawayOrderStatusChangeAuditEvent({
          tx,
          db,
          orderId,
          organizationId,
          branchId,
          fromStatus: "scheduled",
          toStatus: "confirmed",
          actorType: "system",
          actorUid: null,
          reasonCode: "scheduledServiceTimeReached",
          reasonMessage: "Auto-promoted by takeawayOperationsSweep once scheduledFor elapsed.",
          now: nowTimestamp,
        });

        applyKitchenWorkAndStockConsumption(tx, db, stockPlan);
        applyPrintJobPlan(tx, db, printPlan);

        return true;
      });
      if (promoted) processed += 1;
    } catch (error) {
      console.error(`takeawayOperationsSweep: failed promoting ${orderId}`, error);
    }
  }
  return processed;
}

export const takeawayOperationsSweep = onSchedule("every 5 minutes", async () => {
  const db = getFirestore();
  const now = new Date();
  const reverted = await runBranchTakeawaySettingsRevertSweep(db, now);
  const promoted = await runScheduledOrderPromotionSweep(db, now);
  console.log(
    `takeawayOperationsSweep: reverted ${reverted} branch setting(s), promoted ${promoted} scheduled order(s).`,
  );
});
