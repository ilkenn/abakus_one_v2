import { test } from "node:test";
import assert from "node:assert";
import { buildCourierAssignedOrderProjection, COURIER_PII_FIELDS, poolAddressLine } from "../courierPool";
import { roleHasPermission } from "../staffAuthorization";

/** 2026-11-12 (Faz 3a) — pure parts of the delivery pool and the new roles. */

const order = (overrides: Record<string, unknown> = {}) => ({
  channel: "delivery", status: "outForDelivery", organizationId: "org", branchId: "b", orderNumber: "DL-1",
  assignedCourierId: "c1", contactFirstName: "Ayşe", contactLastName: "Demir", contactPhone: "+905321112233",
  deliveryAddressSnapshot: { neighborhoodName: "Caferağa", streetName: "Moda Caddesi", buildingNo: "12" },
  customerNote: "Zile basmayın", paymentMethodSnapshot: { paymentMethodId: "cash" },
  pricing: { grandTotal: { minorUnits: 45000 } },
  ...overrides,
});

test("the courier copy carries the phone until the courier reports delivery", () => {
  const assigned = buildCourierAssignedOrderProjection("o1", order(), "uid-1")!;
  assert.strictEqual(assigned.customerPhone, "+905321112233");
  assert.strictEqual(assigned.status, "assigned");
  assert.strictEqual(assigned.courierAuthUid, "uid-1");
  const delivered = buildCourierAssignedOrderProjection("o1", order({ courierReportedDeliveredAt: 1, departedAt: 1 }), "uid-1")!;
  assert.strictEqual(assigned.customerName, "Ayşe Demir");
  assert.strictEqual(assigned.courierNote, "Zile basmayın");
  assert.ok(String(assigned.addressLine).includes("Moda Caddesi"));
  // ADR-085 stage 2 (KVKK) — name, phone, open address and note all go.
  for (const field of COURIER_PII_FIELDS) assert.ok(!(field in delivered), field);
  assert.strictEqual(delivered.neighborhoodName, "Caferağa");
  assert.strictEqual(delivered.orderNumber, "DL-1");
  assert.strictEqual(delivered.status, "deliveredAwaitingSettlement");
  assert.strictEqual(buildCourierAssignedOrderProjection("o1", order({ departedAt: 1 }), null)!.status, "departed");
});

test("ADR-085 stage 4: the pin travels with the order until delivery", () => {
  const pinned = order({
    deliveryAddressSnapshot: { neighborhoodName: "Caferağa", streetName: "Moda Caddesi", latitude: 40.98, longitude: 29.03 },
  });
  const assigned = buildCourierAssignedOrderProjection("o1", pinned, "uid-1")!;
  assert.strictEqual(assigned.destinationLatitude, 40.98);
  assert.strictEqual(assigned.destinationLongitude, 29.03);
  const delivered = buildCourierAssignedOrderProjection("o1", { ...pinned, courierReportedDeliveredAt: 1 }, "uid-1")!;
  assert.ok(!("destinationLatitude" in delivered));
  assert.ok(!("destinationLatitude" in buildCourierAssignedOrderProjection("o1", order(), "uid-1")!), "no pin, no field");
});

test("ADR-085 stage 4: Trendyol/Getir orders carry the switchboard and the order code; own orders none", () => {
  const own = buildCourierAssignedOrderProjection("o1", order(), "uid-1")!;
  assert.strictEqual(own.marketplaceProvider, null);
  assert.strictEqual(own.switchboardPhone, null);

  const trendyol = buildCourierAssignedOrderProjection(
    "o1", order({ marketplaceProvider: "trendyol", marketplaceOrderCode: "123456" }), "uid-1", "", "02120000000")!;
  assert.strictEqual(trendyol.marketplaceProvider, "trendyol");
  assert.strictEqual(trendyol.marketplaceOrderCode, "123456");
  assert.strictEqual(trendyol.switchboardPhone, "02120000000");

  const yemeksepeti = buildCourierAssignedOrderProjection(
    "o1", order({ marketplaceProvider: "yemeksepeti", marketplaceOrderCode: "YS-9" }), "uid-1")!;
  assert.strictEqual(yemeksepeti.switchboardPhone, null, "Yemeksepeti gives the customer's number");

  const unknown = buildCourierAssignedOrderProjection("o1", order({ marketplaceProvider: "other" }), "uid-1")!;
  assert.strictEqual(unknown.marketplaceProvider, null);
});

test("reserved, closed and unassigned orders", () => {
  const reserved = buildCourierAssignedOrderProjection("o1", order({ status: "preparing", assignedCourierId: undefined, poolReservedCourierId: "c2" }), null)!;
  assert.strictEqual(reserved.status, "reserved");
  assert.strictEqual(reserved.courierId, "c2");
  for (const status of ["completed", "cancelled", "rejected", "refunded"]) {
    assert.strictEqual(buildCourierAssignedOrderProjection("o1", order({ status }), null), null, status);
  }
  assert.strictEqual(buildCourierAssignedOrderProjection("o1", order({ assignedCourierId: undefined }), null), null);
  assert.strictEqual(buildCourierAssignedOrderProjection("o1", order({ channel: "takeaway" }), null), null);
});

test("the pool address line never includes the neighborhood twice or any contact", () => {
  assert.strictEqual(
    poolAddressLine({ neighborhoodName: "Caferağa", streetName: "Moda Caddesi", buildingNo: "12", apartmentNo: "5", floor: "2", addressDescription: "Mavi kapı" }),
    "Moda Caddesi No: 12, Daire: 5, Kat: 2, Mavi kapı",
  );
  assert.strictEqual(poolAddressLine(undefined), "");
});

test("Kasiyer and Mutfak Paket Yetkilisi: staff work + courier dispatch + pool approval, no manager powers", () => {
  for (const role of ["cashier", "packingLead"]) {
    for (const p of ["manageDeliveryOrders", "processPayments", "manageCashSessions", "manageCourierDispatch", "approveCourierPoolRequests"] as const) {
      assert.ok(roleHasPermission(role, p), `${role} ${p}`);
    }
    for (const p of ["approveCashReconciliation", "manageDeliveryOrderCancellations", "manageBranch", "manageStaffRoles"] as const) {
      assert.ok(!roleHasPermission(role, p), `${role} must not have ${p}`);
    }
  }
  for (const role of ["manager", "admin", "tenantOwner"]) assert.ok(roleHasPermission(role, "approveCourierPoolRequests"), role);
  for (const role of ["staff", "courier"]) assert.ok(!roleHasPermission(role, "approveCourierPoolRequests"), role);
});

test("FCM copy: staff request, courier assignment/reservation and rejection reasons", async () => {
  const { poolRequestMessage, assignmentMessage, requestRejectedMessage } = await import("../courierNotifications");
  const req = poolRequestMessage("r1", { courierName: "Ali", orderNumber: "DL-1", neighborhoodName: "Caferağa", amountDueMinorUnits: 45050, orderId: "o1", branchId: "b1" });
  assert.strictEqual(req.body, "Ali · DL-1 (Caferağa) · 450,50 TL");
  assert.deepStrictEqual(req.data, { type: "courierPoolRequest", requestId: "r1", orderId: "o1", branchId: "b1" });
  const reserved = assignmentMessage("o1", { status: "reserved", orderNumber: "DL-1", neighborhoodName: "Caferağa", branchName: "Moda" });
  assert.strictEqual(reserved.title, "Paket size ayrıldı");
  assert.strictEqual(reserved.data.type, "courierReserved");
  assert.strictEqual(assignmentMessage("o1", { status: "assigned", orderNumber: "DL-1" }).body, "DL-1");
  assert.match(requestRejectedMessage("r1", { rejection: "withdrawn", orderNumber: "DL-1", neighborhoodName: "X" }).body, /havuzdan geri alındı/);
  assert.match(requestRejectedMessage("r1", { rejection: "rejected", orderNumber: "DL-1", neighborhoodName: "X" }).body, /talebiniz reddedildi/);
});
