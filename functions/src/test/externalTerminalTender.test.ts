import { test } from "node:test";
import assert from "node:assert";

import { resolveExternalTerminalTender } from "../paymentDomain";
import { summarizeTenderTotals } from "../cashRegisterEngine";
import type { PaymentAttemptDoc } from "../paymentDomain";

/**
 * 2026-11-11 — product owner: card and meal-card payments are taken on the
 * bank's / provider's own terminal and only recorded on the POS; meal cards
 * are reported per brand on the Z report. Pure functions — no emulator.
 */

test("external terminal: a meal card must name a catalog meal-card brand", () => {
  for (const brand of ["pluxee", "multinet", "setcard", "edenred"]) {
    const result = resolveExternalTerminalTender("mealCard", brand, undefined);
    assert.strictEqual(result.status, "ok", brand);
    if (result.status === "ok") assert.strictEqual(result.paymentMethodId, brand);
  }
  const multinet = resolveExternalTerminalTender("mealCard", "multinet", undefined);
  assert.ok(multinet.status === "ok" && multinet.paymentMethodDisplayName === "Multinet");

  assert.strictEqual(resolveExternalTerminalTender("mealCard", undefined, undefined).status, "invalid");
  assert.strictEqual(resolveExternalTerminalTender("mealCard", "visa", undefined).status, "invalid");
  // "cash" is a catalog entry, but not a meal-card brand.
  assert.strictEqual(resolveExternalTerminalTender("mealCard", "cash", undefined).status, "invalid");
});

test("external terminal: card takes no brand; cash and Boncuk are never external", () => {
  const card = resolveExternalTerminalTender("card", undefined, undefined);
  assert.ok(card.status === "ok" && card.paymentMethodId === null && card.paymentMethodDisplayName === "Kredi/Banka Kartı");
  assert.strictEqual(resolveExternalTerminalTender("card", "multinet", undefined).status, "invalid");
  assert.strictEqual(resolveExternalTerminalTender("cash", undefined, undefined).status, "invalid");
  assert.strictEqual(resolveExternalTerminalTender("boncuk", undefined, undefined).status, "invalid");
});

test("external terminal: the slip number is optional, trimmed and length-capped", () => {
  const blank = resolveExternalTerminalTender("card", undefined, "   ");
  assert.ok(blank.status === "ok" && blank.externalSlipNumber === null);
  const slip = resolveExternalTerminalTender("mealCard", "setcard", "  A-123456 ");
  assert.ok(slip.status === "ok" && slip.externalSlipNumber === "A-123456");
  assert.strictEqual(resolveExternalTerminalTender("card", undefined, "x".repeat(65)).status, "invalid");
  assert.strictEqual(resolveExternalTerminalTender("card", undefined, 123456).status, "invalid");
});

function attempt(overrides: Partial<PaymentAttemptDoc>): PaymentAttemptDoc {
  return {
    tenderType: "cash",
    amountMinorUnits: 0,
    currencyCode: "TRY",
    ...overrides,
  } as PaymentAttemptDoc;
}

test("Z report: meal cards are split per brand, never folded into Diğer", () => {
  const totals = summarizeTenderTotals([
    attempt({ tenderType: "cash", amountMinorUnits: 10000 }),
    attempt({ tenderType: "card", amountMinorUnits: 20000 }),
    attempt({ tenderType: "mealCard", amountMinorUnits: 3000, paymentMethodId: "multinet" }),
    attempt({ tenderType: "mealCard", amountMinorUnits: 2000, paymentMethodId: "multinet" }),
    attempt({ tenderType: "mealCard", amountMinorUnits: 4000, paymentMethodId: "pluxee" }),
    attempt({ tenderType: "boncuk", amountMinorUnits: 500 }),
    attempt({ tenderType: "cash", amountMinorUnits: 99999, currencyCode: "EUR" }),
  ], "TRY");

  assert.strictEqual(totals.cashMinorUnits, 10000);
  assert.strictEqual(totals.cardMinorUnits, 20000);
  assert.deepStrictEqual(
    totals.mealCardBreakdown.map((row) => [row.displayName, row.amountMinorUnits]),
    [["Pluxee", 4000], ["Multinet", 5000], ["Setcard", 0], ["Edenred", 0]],
  );
  assert.strictEqual(totals.mealCardMinorUnits, 9000);
  assert.strictEqual(totals.otherMinorUnits, 500);
  assert.strictEqual(totals.totalMinorUnits, 39500);
});

test("Z report: a meal card recorded before brands existed stays in Diğer", () => {
  const totals = summarizeTenderTotals([attempt({ tenderType: "mealCard", amountMinorUnits: 3000 })], "TRY");
  assert.strictEqual(totals.otherMinorUnits, 3000);
  assert.strictEqual(totals.mealCardMinorUnits, 0);
  assert.strictEqual(totals.totalMinorUnits, 3000);
});
