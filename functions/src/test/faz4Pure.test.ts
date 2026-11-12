import { test } from "node:test";
import assert from "node:assert";
import { Timestamp } from "firebase-admin/firestore";

import { roleHasPermission } from "../staffAuthorization";
import { checkMinimumOrder, resolveBranchZone, type BranchDeliveryZone } from "../deliveryZones";
import {
  buildCourierDeliveryReport,
  parseReportRange,
  reportOrderInputFrom,
  type ReportCollectionInput,
  type ReportOrderInput,
} from "../courierDeliveryReport";
import { anonymizedOrderFields, ERASED_CUSTOMER_NAME } from "../erasePosCustomer";

/** 2026-11-12 — Faz 4 pure helpers (no emulator). */

test("Faz 4 permissions: report, minimum override and KVKK erasure are manager-tier and above", () => {
  for (const permission of ["viewDeliveryReports", "overrideDeliveryMinimumOrder", "erasePosCustomerData"] as const) {
    for (const role of ["manager", "admin", "tenantOwner"]) assert.ok(roleHasPermission(role, permission), `${role} ${permission}`);
    for (const role of ["staff", "cashier", "packingLead", "courier"]) {
      assert.ok(!roleHasPermission(role, permission), `${role} must not have ${permission}`);
    }
  }
});

function zone(overrides: Partial<BranchDeliveryZone> = {}): BranchDeliveryZone {
  return {
    id: "z1", districtId: "kadikoy", neighborhoodId: "caferaga", neighborhoodName: "Caferağa",
    minimumOrderMinorUnits: 25000, estimatedDeliveryMinutes: 35, enabled: true, ...overrides,
  };
}

test("resolveBranchZone: a hand-typed neighborhood matches on its slug; disabled and unknown ones do not", () => {
  const zones = [zone(), zone({ id: "z2", neighborhoodId: "moda", neighborhoodName: "Moda", enabled: false })];
  assert.strictEqual(resolveBranchZone(zones, "  CAFERAĞA ", null)?.id, "z1");
  assert.strictEqual(resolveBranchZone(zones, "Moda", null), null, "disabled");
  assert.strictEqual(resolveBranchZone(zones, "Fenerbahçe", null), null, "no rule");
  assert.strictEqual(resolveBranchZone(zones, "", null), null);
});

test("resolveBranchZone: two districts of the branch sharing a name resolve to the default district, else none", () => {
  const zones = [zone({ id: "a", districtId: "kadikoy" }), zone({ id: "b", districtId: "uskudar" })];
  assert.strictEqual(resolveBranchZone(zones, "Caferağa", "uskudar")?.id, "b");
  assert.strictEqual(resolveBranchZone(zones, "Caferağa", null), null, "ambiguous without a default");
});

test("checkMinimumOrder: below, met and no rule", () => {
  assert.deepStrictEqual(checkMinimumOrder(zone(), 18000), {
    status: "below", minimumOrderMinorUnits: 25000, shortfallMinorUnits: 7000,
  });
  assert.deepStrictEqual(checkMinimumOrder(zone(), 25000), { status: "met", minimumOrderMinorUnits: 25000 });
  assert.deepStrictEqual(checkMinimumOrder(zone({ minimumOrderMinorUnits: 0 }), 100), { status: "noRule" });
  assert.deepStrictEqual(checkMinimumOrder(null, 100), { status: "noRule" });
});

const MIN = 60000;
const T0 = Date.parse("2026-11-10T10:00:00.000Z");

function collection(overrides: Partial<ReportCollectionInput>): ReportCollectionInput {
  return {
    orderId: "o1", orderNumber: "DL-1", courierId: "c-shop", paymentMethodId: "cash",
    paymentMethodDisplayName: "Nakit", reportingCategory: "cash", amountMinorUnits: 45000,
    collectedAtMillis: T0 + 60 * MIN, ...overrides,
  };
}

function orderInput(overrides: Partial<ReportOrderInput> = {}): ReportOrderInput {
  return {
    courierType: "internal", neighborhoodName: "Caferağa", createdMillis: T0, readyMillis: T0 + 15 * MIN,
    dispatchedMillis: T0 + 20 * MIN, deliveredMillis: null, ...overrides,
  };
}

test("buildCourierDeliveryReport: per courier, per kind, tender mix, timings, cash difference and pool orders", () => {
  const report = buildCourierDeliveryReport({
    fromIso: "2026-11-10T00:00:00.000Z",
    toIso: "2026-11-11T00:00:00.000Z",
    collections: [
      collection({ orderId: "o1" }),
      collection({ orderId: "o2", orderNumber: "DL-2", paymentMethodId: "credit_card", paymentMethodDisplayName: "Kredi Kartı", reportingCategory: "card", amountMinorUnits: 30000 }),
      collection({ orderId: "o3", orderNumber: "DL-3", courierId: "c-pool", paymentMethodId: "multinet", paymentMethodDisplayName: "Multinet", reportingCategory: "mealCard", amountMinorUnits: 20000 }),
    ],
    settlements: [
      { courierId: "c-shop", courierName: "Mehmet", differenceMinorUnits: -500 },
      { courierId: "c-pool", courierName: "Ali (Dış)", differenceMinorUnits: 0 },
    ],
    orders: new Map([
      ["o1", orderInput()],
      ["o2", orderInput({ readyMillis: T0 + 25 * MIN, dispatchedMillis: T0 + 30 * MIN })],
      // The pool courier tapped "Teslim Ettim" 18 minutes after leaving.
      ["o3", orderInput({ courierType: "pool", neighborhoodName: "Moda", deliveredMillis: T0 + 38 * MIN })],
    ]),
    couriers: new Map([["c-shop", { displayName: "Mehmet", type: "internal" }]]),
  });

  assert.strictEqual(report.totals.packageCount, 3);
  assert.strictEqual(report.totals.collectedMinorUnits, 95000);
  assert.strictEqual(report.totals.cashDifferenceMinorUnits, -500);
  assert.deepStrictEqual(report.totals.paymentMethods.map((m) => m.paymentMethodId), ["cash", "credit_card", "multinet"]);

  assert.strictEqual(report.byKind.internal.packageCount, 2);
  // Preparation: 15 and 25 min → 20. Delivery (no "Teslim Ettim": until the account was closed): 40 and 30 → 35.
  assert.strictEqual(report.byKind.internal.averagePreparationMinutes, 20);
  assert.strictEqual(report.byKind.internal.averageDeliveryMinutes, 35);
  assert.strictEqual(report.byKind.pool.packageCount, 1);
  assert.strictEqual(report.byKind.pool.averageDeliveryMinutes, 18);

  assert.deepStrictEqual(report.couriers.map((c) => [c.courierId, c.courierName, c.courierKind]), [
    ["c-shop", "Mehmet", "internal"],
    ["c-pool", "Ali (Dış)", "pool"],
  ]);
  assert.strictEqual(report.couriers[0].cashDifferenceMinorUnits, -500);
  assert.strictEqual(report.couriers[0].settlementCount, 1);

  assert.strictEqual(report.poolOrders.length, 1);
  assert.deepStrictEqual(
    { ...report.poolOrders[0] },
    {
      orderId: "o3", orderNumber: "DL-3", courierId: "c-pool", courierName: "Ali (Dış)", neighborhoodName: "Moda",
      amountMinorUnits: 20000, paymentMethodId: "multinet", paymentMethodDisplayName: "Multinet",
      collectedAt: new Date(T0 + 60 * MIN).toISOString(), deliveryMinutes: 18,
    },
  );
});

test("buildCourierDeliveryReport: an empty range and orders without timing data", () => {
  const empty = buildCourierDeliveryReport({
    fromIso: "a", toIso: "b", collections: [], settlements: [], orders: new Map(), couriers: new Map(),
  });
  assert.strictEqual(empty.totals.packageCount, 0);
  assert.strictEqual(empty.totals.averagePreparationMinutes, null);
  assert.deepStrictEqual(empty.couriers, []);

  const noTiming = buildCourierDeliveryReport({
    fromIso: "a", toIso: "b", collections: [collection({})], settlements: [],
    orders: new Map([["o1", orderInput({ createdMillis: null, readyMillis: null, dispatchedMillis: null })]]),
    couriers: new Map(),
  });
  assert.strictEqual(noTiming.totals.averagePreparationMinutes, null);
  assert.strictEqual(noTiming.totals.averageDeliveryMinutes, null);
  assert.strictEqual(noTiming.couriers[0].courierName, "c-shop", "falls back to the id");
});

test("reportOrderInputFrom: departure falls back to the outForDelivery history entry, then to ready", () => {
  const base = {
    courierType: "internal",
    deliveryAddressSnapshot: { neighborhoodName: "Caferağa" },
    timestamps: { created: "2026-11-10T10:00:00.000Z", ready: "2026-11-10T10:15:00.000Z" },
  };
  const withHistory = reportOrderInputFrom({
    ...base,
    statusHistory: [{ newValue: "outForDelivery", timestamp: "2026-11-10T10:21:00.000Z" }],
  });
  assert.strictEqual(withHistory.dispatchedMillis, Date.parse("2026-11-10T10:21:00.000Z"));
  const departed = reportOrderInputFrom({ ...base, departedAt: Timestamp.fromMillis(T0 + 22 * MIN) });
  assert.strictEqual(departed.dispatchedMillis, T0 + 22 * MIN);
  assert.strictEqual(reportOrderInputFrom(base).dispatchedMillis, Date.parse("2026-11-10T10:15:00.000Z"));
  assert.strictEqual(reportOrderInputFrom(base).neighborhoodName, "Caferağa");
});

test("parseReportRange: ISO bounds, order and the 92-day cap", () => {
  const { from, to } = parseReportRange("2026-11-01T00:00:00.000Z", "2026-11-12T00:00:00.000Z");
  assert.strictEqual(to.getTime() - from.getTime(), 11 * 86400000);
  assert.throws(() => parseReportRange("2026-11-12T00:00:00Z", "2026-11-01T00:00:00Z"));
  assert.throws(() => parseReportRange("2026-01-01T00:00:00Z", "2026-11-01T00:00:00Z"));
  assert.throws(() => parseReportRange("dün", "bugün"));
  assert.throws(() => parseReportRange(undefined, "2026-11-01T00:00:00Z"));
});

test("anonymizedOrderFields: name, phone, notes and the open address go; neighborhood, amounts and items stay", () => {
  const now = Timestamp.fromMillis(T0);
  const fields = anonymizedOrderFields({
    contactFirstName: "Ayşe", contactLastName: "Demir", contactPhone: "+905321112233", customerNote: "Zile basmayın",
    posCustomerId: "org_hash",
    lines: [{ productName: "Bowl", quantity: 2, customerNote: "Ayşe Hanım için" }],
    deliveryAddressSnapshot: {
      neighborhoodName: "Caferağa", districtId: "kadikoy", streetName: "Moda Caddesi", buildingNo: "12",
      apartmentNo: "4", floor: "2", addressDescription: "Eczanenin üstü", label: "Ev", latitude: 41, longitude: 29,
      savedAddressId: "org_hash", providerPlaceId: "p1",
    },
    pricing: { grandTotal: { minorUnits: 45000 } },
  }, "erasure-1", now);

  assert.strictEqual(fields.contactFirstName, ERASED_CUSTOMER_NAME);
  assert.strictEqual(fields.contactLastName, "");
  assert.strictEqual(fields.contactPhone, null);
  assert.strictEqual(fields.customerNote, "");
  assert.strictEqual(fields.posCustomerId, null);
  assert.deepStrictEqual(fields.lines, [{ productName: "Bowl", quantity: 2, customerNote: "" }]);
  const address = fields.deliveryAddressSnapshot as Record<string, unknown>;
  assert.strictEqual(address.neighborhoodName, "Caferağa");
  assert.strictEqual(address.districtId, "kadikoy");
  for (const key of ["streetName", "apartmentNo", "label"]) assert.strictEqual(address[key], "", key);
  for (const key of ["buildingNo", "floor", "addressDescription", "latitude", "longitude", "savedAddressId", "providerPlaceId"]) {
    assert.strictEqual(address[key], null, key);
  }
  assert.ok(!("pricing" in fields), "amounts untouched");
  assert.deepStrictEqual(fields.personalDataErasure, { erasureId: "erasure-1", erasedAt: now });

  const noAddress = anonymizedOrderFields({ contactFirstName: "A" }, "e", now);
  assert.ok(!("deliveryAddressSnapshot" in noAddress));
  assert.ok(!("lines" in noAddress));
});
