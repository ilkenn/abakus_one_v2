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
 * **Wired into all four channels as of P8-C.3 (2026-08-25).** Written as
 * foundation-only in P8-B (no channel called it yet, each kept its own
 * duplicated two-benefit `if`). Each channel's own campaign-integration
 * phase then replaced that duplicated check with a single call to
 * [enforceBenefitExclusivity] as this comment originally predicted:
 * `submitTakeawayOrder.ts` (P8-C), `submitDeliveryOrder.ts` (P8-C.1),
 * `reservationPreorder.ts` (P8-C.2, called from `parsePreorderRequest` where
 * the preorder's three benefit fields are parsed together — not from
 * `submitReservation.ts` directly), and `submitDineInOrder.ts` (P8-C.3).
 * All four now enforce the same three-way (Boncuk / catalog reward /
 * campaign) exclusivity through this one function — no channel hand-rolls
 * its own stacking check anymore.
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
