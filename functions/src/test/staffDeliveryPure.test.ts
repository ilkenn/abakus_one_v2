import { test } from "node:test";
import assert from "node:assert";

import { normalizeTurkishPhone, rememberAddress, MAX_REMEMBERED_ADDRESSES, type PosCustomerAddress } from "../posCustomerBook";
import { parseDeliveryFee, priceWithDeliveryFee } from "../submitStaffDeliveryOrder";
import { buildOrderLine } from "../takeawayPricing";

/** 2026-11-11 — Faz 2 pure helpers (no emulator). */

test("normalizeTurkishPhone: the shapes cashiers type all become one E.164 number", () => {
  for (const raw of ["0532 111 22 33", "05321112233", "5321112233", "+90 532 111 22 33", "90 (532) 111-22-33"]) {
    assert.strictEqual(normalizeTurkishPhone(raw), "+905321112233", raw);
  }
  assert.strictEqual(normalizeTurkishPhone("0216 333 44 55"), "+902163334455", "landline");
  for (const raw of ["12345", "0132 111 22 33", "+1 202 555 0100", ""]) {
    assert.strictEqual(normalizeTurkishPhone(raw), null, raw);
  }
});

function address(streetName: string, buildingNo = "1"): PosCustomerAddress {
  return {
    label: "", neighborhoodName: "Moda", streetName, buildingNo, apartmentNo: "", floor: "",
    addressDescription: "", lastUsedAt: "2026-11-11T10:00:00.000Z",
  };
}

test("rememberAddress: the used address moves to the front, duplicates collapse, at most 5 kept", () => {
  const list = [address("A"), address("B"), address("C")];
  assert.deepStrictEqual(rememberAddress(list, address("B")).map((a) => a.streetName), ["B", "A", "C"]);
  assert.deepStrictEqual(
    rememberAddress(list, { ...address("b"), addressDescription: "yeni tarif" }).map((a) => a.addressDescription),
    ["yeni tarif", "", ""],
    "same place (case-insensitive) is replaced, not duplicated",
  );
  const long = ["A", "B", "C", "D", "E"].map((s) => address(s));
  const result = rememberAddress(long, address("F"));
  assert.strictEqual(result.length, MAX_REMEMBERED_ADDRESSES);
  assert.deepStrictEqual(result.map((a) => a.streetName), ["F", "A", "B", "C", "D"]);
});

test("priceWithDeliveryFee: the fee is added to the total with its own 20% VAT", () => {
  const line = buildOrderLine({
    productId: "p", productName: "P", modifiers: [], quantity: 1, unitPriceMinorUnits: 61000, taxBasisPoints: 1000,
  });
  const noFee = priceWithDeliveryFee([line], 0);
  assert.strictEqual(noFee.grandTotalMinorUnits, 61000);
  assert.strictEqual(noFee.deliveryFeeVatMinorUnits, 0);

  const withFee = priceWithDeliveryFee([line], 3000);
  assert.strictEqual(withFee.grandTotalMinorUnits, 64000);
  assert.strictEqual(withFee.deliveryFeeVatMinorUnits, 500, "30 TL gross at 20% → 5 TL VAT");
  assert.strictEqual(withFee.vatAmountMinorUnits, noFee.vatAmountMinorUnits + 500);
  assert.strictEqual(withFee.taxableBaseMinorUnits, noFee.taxableBaseMinorUnits + 2500);
});

test("parseDeliveryFee: absent is 0; only whole minor units in [0, 1.000 TL]", () => {
  assert.strictEqual(parseDeliveryFee(undefined), 0);
  assert.strictEqual(parseDeliveryFee(2500), 2500);
  for (const raw of [-1, 1.5, 100001, "30"]) {
    assert.throws(() => parseDeliveryFee(raw), String(raw));
  }
});
