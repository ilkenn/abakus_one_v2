import { boncukError } from "./boncukRedemptionErrors";

/**
 * `benefitExclusivity` — Server-Authoritative Campaign Engine P8-B
 * (2026-08-25).
 *
 * **The one shared "ONE ORDER = MAXIMUM ONE BENEFIT" enforcement point**
 * (locked P8-A/P8-B decision). Today, each of the four `submit*Order.ts`
 * channels hand-duplicates its own identical `requestedBoncukAmount > 0 &&
 * selectedRewardId !== null` stacking check (confirmed by the P8-A audit —
 * byte-identical bodies in `submitTakeawayOrder.ts`, `submitDeliveryOrder
 * .ts`, `submitDineInOrder.ts`, `reservationPreorder.ts`). Adding a THIRD
 * benefit (campaign) the same copy-paste way would mean six pairwise
 * stacking combinations hand-duplicated four times — this module exists so
 * that never has to happen: one call, one place, one rule.
 *
 * **Not yet wired into any `submit*Order.ts` file (P8-B is foundation
 * only).** This phase does not touch checkout/order-submission code at
 * all — the existing four files keep their own existing (already-tested,
 * already-correct) two-benefit checks unchanged. A future
 * checkout-integration phase (P8-C+), when it adds `selectedCampaignId` as
 * a real request field to a channel, is expected to REPLACE that channel's
 * own duplicated check with a single call to [enforceBenefitExclusivity]
 * rather than hand-adding a third `if` — but that replacement is itself
 * deferred to that phase, not performed here.
 *
 * **Fails closed, never silently prioritizes.** If a request names more
 * than one benefit, the whole request is rejected before any pricing,
 * balance read, or transaction begins — never "campaign wins," never
 * "Boncuk wins," never a silent drop of the second selection.
 */

export interface RequestedBenefits {
  /** `0` (or omitted, per `sanitizeRequestedBoncukAmount`'s own convention) means "no Boncuk requested." */
  requestedBoncukAmount: number;
  selectedRewardId: string | null;
  selectedCampaignId: string | null;
}

export function enforceBenefitExclusivity(benefits: RequestedBenefits): void {
  const selectedCount = [
    benefits.requestedBoncukAmount > 0,
    benefits.selectedRewardId !== null,
    benefits.selectedCampaignId !== null,
  ].filter(Boolean).length;

  if (selectedCount > 1) {
    boncukError(
      "invalid-argument",
      "At most one benefit (Boncuk redemption, catalog reward, or campaign) may be selected per order.",
      "benefit/stacking-not-allowed",
    );
  }
}
