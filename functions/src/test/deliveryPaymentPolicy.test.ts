import { test } from "node:test";
import assert from "node:assert";
import {
  DELIVERY_ENABLED_PAYMENT_METHOD_IDS,
  isEnabledForDeliveryCheckout,
} from "../deliveryPaymentPolicy";

/**
 * Pure, no-emulator unit tests — Faz P.1. Mirrors `takeawayPricing.test.ts`'s
 * own "no Firestore/Functions/Auth emulator involved" shape: every function
 * under test here is a pure function of its arguments.
 */

test("DELIVERY_ENABLED_PAYMENT_METHOD_IDS contains exactly the 7 LOCKED COD method ids (req 12)", () => {
  assert.strictEqual(DELIVERY_ENABLED_PAYMENT_METHOD_IDS.size, 7);
  for (const id of [
    "cash",
    "credit_card",
    "pluxee",
    "multinet",
    "setcard",
    "edenred",
    "metropol_card",
  ]) {
    assert.strictEqual(DELIVERY_ENABLED_PAYMENT_METHOD_IDS.has(id), true, id);
  }
});

test("isEnabledForDeliveryCheckout: cash is enabled", () => {
  assert.strictEqual(isEnabledForDeliveryCheckout("cash"), true);
});

test("isEnabledForDeliveryCheckout: bank_transfer is excluded (req 14)", () => {
  assert.strictEqual(isEnabledForDeliveryCheckout("bank_transfer"), false);
});

test("isEnabledForDeliveryCheckout: gift_voucher is excluded (req 15)", () => {
  assert.strictEqual(isEnabledForDeliveryCheckout("gift_voucher"), false);
});

test("isEnabledForDeliveryCheckout: an online-payment-style method id is rejected by default-deny semantics (req 13)", () => {
  assert.strictEqual(isEnabledForDeliveryCheckout("online_credit_card"), false);
});

test("isEnabledForDeliveryCheckout: an arbitrary unseeded method id cannot pass (req 16)", () => {
  assert.strictEqual(isEnabledForDeliveryCheckout("some_future_method"), false);
});
