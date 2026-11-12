import { test } from "node:test";
import assert from "node:assert";
import { buildCourierAssignedOrderProjection, poolAddressLine } from "../courierPool";
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
  assert.ok(!("customerPhone" in delivered));
  assert.strictEqual(delivered.status, "deliveredAwaitingSettlement");
  assert.strictEqual(buildCourierAssignedOrderProjection("o1", order({ departedAt: 1 }), null)!.status, "departed");
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
