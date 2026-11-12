import { test } from "node:test";
import assert from "node:assert";

import { computeCourierSettlement, orderAmountDueMinorUnits, reportingCategoryFor } from "../courierSettlement";
import { summarizeDailyRevenue } from "../cashRegisterEngine";

/** 2026-11-11 — Faz 2b pure helpers (no emulator). */

test("computeCourierSettlement: expected cash is the cash-paid orders only; difference = received − expected", () => {
  const result = computeCourierSettlement([
    { orderId: "a", amountDueMinorUnits: 20000, paymentMethodId: "cash" },
    { orderId: "b", amountDueMinorUnits: 10000, paymentMethodId: "credit_card" },
    { orderId: "c", amountDueMinorUnits: 15000, paymentMethodId: "multinet" },
  ], 19000);
  assert.strictEqual(result.expectedCashMinorUnits, 20000);
  assert.strictEqual(result.differenceMinorUnits, -1000);
  assert.strictEqual(result.totalCollectedMinorUnits, 45000);
  assert.deepStrictEqual(result.totalsByPaymentMethod, { cash: 20000, credit_card: 10000, multinet: 15000 });
});

test("orderAmountDueMinorUnits: the total, or what is left after Boncuk", () => {
  assert.strictEqual(orderAmountDueMinorUnits({ pricing: { grandTotal: { minorUnits: 61000 } } }), 61000);
  assert.strictEqual(
    orderAmountDueMinorUnits({ pricing: { grandTotal: { minorUnits: 61000 } }, boncukRedemption: { remainingPayableMinorUnits: 51000 } }),
    51000,
  );
});

test("reportingCategoryFor: cash / card / meal-card brands", () => {
  assert.strictEqual(reportingCategoryFor("cash"), "cash");
  assert.strictEqual(reportingCategoryFor("credit_card"), "card");
  assert.strictEqual(reportingCategoryFor("edenred"), "mealCard");
  assert.strictEqual(reportingCategoryFor("nope"), null);
});

test("summarizeDailyRevenue: collections join their tender lines; Paket Servis total and Kurye Farkı reported", () => {
  const totals = summarizeDailyRevenue({
    attempts: [{ tenderType: "cash", amountMinorUnits: 5000, currencyCode: "TRY" } as never],
    deliveryCollections: [
      { reportingCategory: "cash", paymentMethodId: "cash", paymentMethodDisplayName: "Nakit", amountMinorUnits: 20000, currencyCode: "TRY" },
      { reportingCategory: "card", paymentMethodId: "credit_card", paymentMethodDisplayName: "Kredi Kartı", amountMinorUnits: 10000, currencyCode: "TRY" },
      { reportingCategory: "mealCard", paymentMethodId: "setcard", paymentMethodDisplayName: "Setcard", amountMinorUnits: 7000, currencyCode: "TRY" },
    ],
    courierSettlements: [{ differenceMinorUnits: -1000, currencyCode: "TRY" }, { differenceMinorUnits: 500, currencyCode: "TRY" }],
    currencyCode: "TRY",
  });
  assert.strictEqual(totals.cashMinorUnits, 25000);
  assert.strictEqual(totals.cardMinorUnits, 10000);
  assert.strictEqual(totals.mealCardBreakdown.find((r) => r.paymentMethodId === "setcard")!.amountMinorUnits, 7000);
  assert.strictEqual(totals.deliveryCollectionMinorUnits, 37000);
  assert.strictEqual(totals.courierDifferenceMinorUnits, -500);
  assert.strictEqual(totals.totalMinorUnits, 42000);
});
