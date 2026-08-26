import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { releaseCampaignUsage } from "./campaignUsage";

/**
 * `campaignUsageRestore` — Server-Authoritative Campaign Engine P8-C
 * (2026-08-25).
 *
 * Consumes `onOrderTerminalFailureOrRefund.ts`'s `order.rejected`/
 * `order.cancelled`/`order.refunded` outbox records to release a
 * previously reserved campaign usage slot — the direct campaign sibling of
 * `loyaltyRedemptionRestore.ts`, mirroring its exact thin-trigger/
 * pure-function outbox-consumer shape. Deliberately a SEPARATE consumer,
 * never folded into `loyaltyRedemptionRestore.ts` itself — campaign usage
 * is `campaignUsageCounters`/`campaignCustomerUsage`/
 * `campaignUsageReservations` accounting, not a Loyalty ledger concept, and
 * "one order = maximum one benefit family" (`BR-LOYALTY-006`) already
 * guarantees an order carrying a `campaign` snapshot never also carries a
 * `boncukRedemption`/`catalogReward` one — `loyaltyRedemptionRestore.ts`
 * itself needs zero changes.
 *
 * **Channel-agnostic by construction, exactly like every other outbox
 * consumer in this codebase** — this consumer does not check
 * `orderData.channel === "takeaway"` anywhere. It reacts to whether the
 * order's own `selectedBenefitType === "campaign"`. Written when only
 * `submitTakeawayOrder.ts` (P8-C) set that field; confirmed still true, with
 * zero further change to this file, as `submitDeliveryOrder.ts` (P8-C.1),
 * `reservationPreorder.ts`/`submitReservation.ts` (P8-C.2), and
 * `submitDineInOrder.ts` (P8-C.3) each independently started setting the
 * same field on their own orders — exactly the extensibility this comment
 * originally predicted.
 *
 * **Never re-reads live campaign rules/limits.** The order's own immutable
 * `campaign` snapshot supplies the only two values this consumer needs
 * (`organizationId` from the order document itself, `campaignId` from the
 * snapshot) — the `campaigns/{campaignId}` document itself is never read.
 *
 * **Idempotent, never negative.** [releaseCampaignUsage] itself is the
 * true idempotency guarantee (its own deterministic reservation-document
 * state, `campaignUsage.ts`) — `campaignUsageReleaseEvaluated` on the
 * event document is a monitoring/consistency flag only, re-asserted on
 * every genuine success or deterministic no-op, mirroring
 * `boncukRedemptionRestoreEvaluated`'s own exact discipline.
 *
 * **Never releases on successful completion** — structurally, not by a
 * special case: `onOrderCompleted.ts` is a completely separate trigger
 * that writes its own `order.completed` outbox event, which this consumer
 * never subscribes to at all (`TERMINAL_EVENT_TYPE_TO_ORDER_STATUS` below
 * has no `order.completed` key). A campaign's reserved usage is therefore
 * permanent the moment an order reaches `completed`, exactly mirroring how
 * Boncuk earning/redemption never gets "un-earned"/"un-spent" on
 * completion either.
 */

const TERMINAL_EVENT_TYPE_TO_ORDER_STATUS: Record<string, string> = {
  "order.rejected": "rejected",
  "order.cancelled": "cancelled",
  "order.refunded": "refunded",
};

export interface ProcessOrderTerminalEventForCampaignUsageReleaseResult {
  processed: boolean;
  reason: string;
}

function orderEventsCollection(db: Firestore) {
  return db.collection("orderEvents");
}

/**
 * The actual business logic — called both by the trigger's fast path and
 * directly by tests, mirroring `processOrderTerminalEventForBoncukRedemptionRestore`'s
 * own pure-ish-function/thin-trigger-wrapper split.
 */
export async function processOrderTerminalEventForCampaignUsageRelease(
  db: Firestore,
  eventId: string,
  eventData: Record<string, unknown> | undefined,
  now: Timestamp = Timestamp.now(),
): Promise<ProcessOrderTerminalEventForCampaignUsageReleaseResult> {
  if (!eventData) return { processed: false, reason: "missing-event" };

  const type = eventData.type as string | undefined;
  const expectedOrderStatus = type ? TERMINAL_EVENT_TYPE_TO_ORDER_STATUS[type] : undefined;
  if (!expectedOrderStatus) {
    // Not a terminal-failure/refund event this consumer reacts to (e.g.
    // order.completed, or any other future event type) — ignore safely.
    return { processed: false, reason: "not-a-terminal-failure-or-refund-event" };
  }

  const orderId = eventData.orderId as string | undefined;
  const organizationId = eventData.organizationId as string | null | undefined;
  if (!orderId || !organizationId) {
    logger.error(
      `[campaignUsageRestore] malformed ${type} event ${eventId} — missing orderId/organizationId.`,
    );
    return { processed: false, reason: "malformed-event" };
  }

  const eventRef = orderEventsCollection(db).doc(eventId);
  const orderRef = db.collection("orders").doc(orderId);

  return db.runTransaction(
    async (tx): Promise<ProcessOrderTerminalEventForCampaignUsageReleaseResult> => {
      // Reads first, always. The real order document is read — and fully
      // validated — before ever deciding there's nothing to release,
      // mirroring `loyaltyRedemptionRestore.ts`'s own defense-in-depth
      // ordering exactly: an anomaly here must win over "no campaign, no
      // work to do," since it's a distinct, retryable failure mode this
      // consumer must never silently swallow as a no-op.
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        logger.error(
          `[campaignUsageRestore] order ${orderId} referenced by event ${eventId} not found.`,
        );
        return { processed: false, reason: "order-document-missing" };
      }
      const orderData = orderSnap.data()!;

      if (orderData.status !== expectedOrderStatus) {
        logger.error(
          `[campaignUsageRestore] order ${orderId} status mismatch for event ${eventId} — event claims "${expectedOrderStatus}", document reads "${String(orderData.status)}".`,
        );
        return { processed: false, reason: "order-status-mismatch" };
      }
      if (orderData.organizationId !== organizationId) {
        logger.error(
          `[campaignUsageRestore] order ${orderId} organizationId mismatch against event ${eventId}.`,
        );
        return { processed: false, reason: "order-identity-mismatch" };
      }

      if (orderData.selectedBenefitType !== "campaign" || !orderData.campaign) {
        // No campaign was ever used on this order — nothing to release. A
        // clean, deterministic no-op, correctly marked evaluated.
        tx.set(eventRef, { campaignUsageReleaseEvaluated: true }, { merge: true });
        return { processed: true, reason: "no-campaign-to-release" };
      }

      const campaignSnapshot = orderData.campaign as Record<string, unknown>;
      const campaignId = campaignSnapshot.campaignId;
      if (typeof campaignId !== "string" || campaignId.length === 0) {
        logger.error(
          `[campaignUsageRestore] order ${orderId}'s campaign snapshot has a malformed campaignId — failing closed rather than guessing.`,
        );
        return { processed: false, reason: "malformed-campaign-snapshot" };
      }

      // Never re-reads `campaigns/{campaignId}` — releaseCampaignUsage
      // works entirely off the deterministic reservation document derived
      // from (organizationId, campaignId, orderId).
      const result = await releaseCampaignUsage(db, tx, { organizationId, campaignId, orderId }, now);

      tx.set(eventRef, { campaignUsageReleaseEvaluated: true }, { merge: true });
      return { processed: true, reason: result.status };
    },
  );
}

export const onOrderEventCreatedForCampaignUsageRelease = onDocumentCreated(
  "orderEvents/{eventId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const db = getFirestore();
    await processOrderTerminalEventForCampaignUsageRelease(db, event.params.eventId, snapshot.data());
  },
);
