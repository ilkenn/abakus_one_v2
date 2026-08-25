import { test } from "node:test";
import assert from "node:assert";
import { HttpsError } from "firebase-functions/v2/https";
import { enforceBenefitExclusivity } from "../benefitExclusivity";

/**
 * Pure, no-emulator unit tests for the shared "ONE ORDER = MAXIMUM ONE
 * BENEFIT" enforcement helper — Server-Authoritative Campaign Engine P8-B
 * (2026-08-25).
 */

test("enforceBenefitExclusivity: no benefit selected — passes", () => {
  assert.doesNotThrow(() =>
    enforceBenefitExclusivity({ requestedBoncukAmount: 0, selectedRewardId: null, selectedCampaignId: null }),
  );
});

test("enforceBenefitExclusivity: exactly one of the three — each passes independently", () => {
  assert.doesNotThrow(() =>
    enforceBenefitExclusivity({ requestedBoncukAmount: 5, selectedRewardId: null, selectedCampaignId: null }),
  );
  assert.doesNotThrow(() =>
    enforceBenefitExclusivity({ requestedBoncukAmount: 0, selectedRewardId: "reward-1", selectedCampaignId: null }),
  );
  assert.doesNotThrow(() =>
    enforceBenefitExclusivity({ requestedBoncukAmount: 0, selectedRewardId: null, selectedCampaignId: "campaign-1" }),
  );
});

test("enforceBenefitExclusivity: Boncuk + catalog reward together fails closed", () => {
  assert.throws(
    () =>
      enforceBenefitExclusivity({ requestedBoncukAmount: 5, selectedRewardId: "reward-1", selectedCampaignId: null }),
    (error: unknown) => {
      assert.ok(error instanceof HttpsError);
      assert.strictEqual(error.code, "invalid-argument");
      assert.strictEqual((error.details as { reason: string }).reason, "benefit/stacking-not-allowed");
      return true;
    },
  );
});

test("enforceBenefitExclusivity: Boncuk + campaign together fails closed", () => {
  assert.throws(() =>
    enforceBenefitExclusivity({ requestedBoncukAmount: 5, selectedRewardId: null, selectedCampaignId: "campaign-1" }),
  );
});

test("enforceBenefitExclusivity: catalog reward + campaign together fails closed", () => {
  assert.throws(() =>
    enforceBenefitExclusivity({
      requestedBoncukAmount: 0,
      selectedRewardId: "reward-1",
      selectedCampaignId: "campaign-1",
    }),
  );
});

test("enforceBenefitExclusivity: all three at once fails closed, never silently prioritizes one", () => {
  assert.throws(() =>
    enforceBenefitExclusivity({
      requestedBoncukAmount: 5,
      selectedRewardId: "reward-1",
      selectedCampaignId: "campaign-1",
    }),
  );
});
