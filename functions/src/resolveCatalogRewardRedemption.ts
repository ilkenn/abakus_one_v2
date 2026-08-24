import { Timestamp, type Firestore, type Transaction } from "firebase-admin/firestore";
import {
  LOYALTY_REWARD_CATALOG_COLLECTION,
  isRewardCurrentlyValid,
  parseLoyaltyRewardCatalogEntry,
  type LoyaltyRewardCatalogEntry,
  type CanonicalCommercialChannel,
} from "./loyaltyRewardCatalog";

/**
 * `resolveCatalogRewardRedemption` — Boncuk Loyalty Program P7-B
 * (2026-08-24).
 *
 * The pure, server-authoritative foundation for future checkout-time
 * catalog-reward redemption (P7-C, NOT built yet — this file never debits
 * an account and never writes a `catalogRedemption` ledger entry). Mirrors
 * `loyaltyRedemption.ts`'s own split exactly: an I/O loader
 * ([loadLoyaltyRewardForRedemption], the transactional read) separate from
 * a pure calculator ([resolveCatalogRewardRedemption], no I/O, fully unit-
 * testable) — the same shape `calculateBoncukRedemption`/
 * `resolveAccountForRedemption` already established for cash redemption.
 *
 * **Deliberately NOT `calculateBoncukRedemption`.** That function's
 * 50%-of-order-cap math computes a proportional cash discount against an
 * order total — a catalog reward is a fixed-cost exchange for one specific
 * item, an entirely different shape of calculation. Reusing that function
 * here would silently apply a cap concept that makes no sense for "give
 * this exact item for exactly N Boncuk," so this module has its own,
 * independent, much simpler resolution logic instead.
 */

export interface CatalogRewardRedemptionSnapshot {
  rewardId: string;
  rewardVersion: number;
  title: string;
  boncukCost: number;
  redeemedProductId: string;
}

export type CatalogRewardRedemptionResult =
  | { status: "ok"; snapshot: CatalogRewardRedemptionSnapshot }
  | { status: "reward-not-found" }
  | { status: "organization-mismatch" }
  | { status: "reward-not-currently-valid" }
  | { status: "channel-not-eligible" }
  | { status: "product-not-eligible" }
  | { status: "insufficient-balance"; requiredBoncuk: number; availableBoncuk: number };

/**
 * The transactional read half — loads the LIVE reward document (the
 * current version is always read directly off the live doc's own
 * `version` field; `loyaltyRewardCatalogVersions` exists for audit
 * history, not as the primary redemption-time read path). Returns `null`
 * for a missing OR malformed/corrupt document — both fail closed
 * identically from the caller's perspective (`reward-not-found` in
 * [resolveCatalogRewardRedemption] below), never throwing on a corrupt
 * document.
 */
export async function loadLoyaltyRewardForRedemption(
  db: Firestore,
  rewardId: string,
  tx?: Transaction,
): Promise<LoyaltyRewardCatalogEntry | null> {
  const ref = db.collection(LOYALTY_REWARD_CATALOG_COLLECTION).doc(rewardId);
  const snap = tx ? await tx.get(ref) : await ref.get();
  if (!snap.exists) return null;
  return parseLoyaltyRewardCatalogEntry(snap.data());
}

/**
 * Pure — no Firestore access, no writes, throws nothing. The caller (P7-C)
 * is responsible for: loading the reward via [loadLoyaltyRewardForRedemption]
 * inside its own transaction (alongside every other read that transaction
 * needs, before any write — the same discipline every other redemption
 * path in this codebase already follows), resolving `organizationId`
 * server-side (never client-supplied), and reading the account's current
 * `spendableBalance`. This function only decides whether the exchange is
 * currently valid and, if so, returns the immutable proposed snapshot the
 * caller will later persist onto the order document and the
 * `catalogRedemption` ledger entry — never client-supplied `boncukCost`/
 * `title`/`rewardVersion`, always server-resolved from the reward
 * [loadLoyaltyRewardForRedemption] loaded.
 */
export function resolveCatalogRewardRedemption(params: {
  reward: LoyaltyRewardCatalogEntry | null;
  now: Date;
  organizationId: string;
  /**
   * The real, server-derived commercial channel of THIS order (e.g.
   * `"takeaway"`) — never client-supplied. P7-C.1: a reward is only
   * redeemable on a channel its own `eligibleChannels` lists.
   */
  orderChannel: CanonicalCommercialChannel;
  requestedProductId: string;
  spendableBalance: number;
}): CatalogRewardRedemptionResult {
  const { reward, now, organizationId, orderChannel, requestedProductId, spendableBalance } = params;
  if (reward === null) return { status: "reward-not-found" };
  if (reward.organizationId !== organizationId) return { status: "organization-mismatch" };
  if (!isRewardCurrentlyValid(reward, Timestamp.fromDate(now))) {
    return { status: "reward-not-currently-valid" };
  }
  if (!reward.eligibleChannels.includes(orderChannel)) {
    return { status: "channel-not-eligible" };
  }
  if (!reward.eligibleProductIds.includes(requestedProductId)) {
    return { status: "product-not-eligible" };
  }
  if (spendableBalance < reward.boncukCost) {
    return {
      status: "insufficient-balance",
      requiredBoncuk: reward.boncukCost,
      availableBoncuk: spendableBalance,
    };
  }
  return {
    status: "ok",
    snapshot: {
      rewardId: reward.rewardId,
      rewardVersion: reward.version,
      title: reward.title,
      boncukCost: reward.boncukCost,
      redeemedProductId: requestedProductId,
    },
  };
}
