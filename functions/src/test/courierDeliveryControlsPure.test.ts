import { test } from "node:test";
import assert from "node:assert";
import { paymentNeedsSlip, resolveDeliveryPayment } from "../courierDeliveryControls";

/** ADR-085 stage 6B — which method "Teslim Ettim" records, and when a slip photo is needed. */

test("a slip is needed for a card on the POS and every meal card, not for cash", () => {
  for (const id of ["credit_card", "pluxee", "multinet", "setcard", "edenred", "metropol_card"]) {
    assert.strictEqual(paymentNeedsSlip(id), true, id);
  }
  assert.strictEqual(paymentNeedsSlip("cash"), false);
});

test("pay-on-delivery orders switch only between pay-on-delivery methods; a switch is a change", () => {
  assert.deepStrictEqual(resolveDeliveryPayment("cash", "cash"), { methodId: "cash", changed: false, needsSlip: false, collected: true });
  assert.deepStrictEqual(resolveDeliveryPayment("cash", "metropol_card"), { methodId: "metropol_card", changed: true, needsSlip: true, collected: true });
  assert.throws(() => resolveDeliveryPayment("cash", "online_card"), /paymentMethodId must be/);
  assert.throws(() => resolveDeliveryPayment("cash", null), /paymentMethodId must be/);
});

test("an online order keeps its method", () => {
  assert.deepStrictEqual(resolveDeliveryPayment("online_card", null), { methodId: "online_card", changed: false, needsSlip: false, collected: false });
  assert.deepStrictEqual(resolveDeliveryPayment("online_card", "online_card").changed, false);
  assert.throws(() => resolveDeliveryPayment("online_card", "cash"), /cannot change/);
});
