import { test } from "node:test";
import assert from "node:assert";
import type { CallableRequest } from "firebase-functions/v2/https";
import {
  roleHasPermission,
  DEFAULT_STAFF_ROLE_PERMISSIONS,
  requireStaffPermission,
  requireBranchAccess,
  type StaffPermission,
} from "../staffAuthorization";

// Pure-function tests — no emulator needed. Faz R.1B.1 REQUIRED fix #1:
// proves `roleHasPermission` is a genuine, data-driven permission resolver
// (role is only an input), not a hardcoded role-name check — by exercising
// it against role/permission combinations the *default* mapping has no
// opinion on, via the explicit `rolePermissions` override parameter.

test("roleHasPermission: manager has manageReservations under the default (canonical) mapping", () => {
  assert.strictEqual(roleHasPermission("manager", "manageReservations"), true);
});

test("roleHasPermission: admin has manageReservations under the default mapping", () => {
  assert.strictEqual(roleHasPermission("admin", "manageReservations"), true);
});

test("roleHasPermission: tenantOwner has manageReservations under the default mapping", () => {
  assert.strictEqual(roleHasPermission("tenantOwner", "manageReservations"), true);
});

test("roleHasPermission: base staff does NOT have manageReservations under the default mapping", () => {
  assert.strictEqual(roleHasPermission("staff", "manageReservations"), false);
});

test("roleHasPermission: courier does NOT have manageReservations under the default mapping", () => {
  assert.strictEqual(roleHasPermission("courier", "manageReservations"), false);
});

test("roleHasPermission: an unknown role name never has any permission", () => {
  assert.strictEqual(roleHasPermission("not-a-real-role", "manageReservations"), false);
});

test("roleHasPermission: a role outside the default manager-tier can be granted manageReservations via an explicit override map, with zero change to the resolver itself — proves role is only an input to permission resolution", () => {
  const grantedToStaff = {
    ...DEFAULT_STAFF_ROLE_PERMISSIONS,
    staff: ["manageReservations"] as const,
  };
  assert.strictEqual(roleHasPermission("staff", "manageReservations", grantedToStaff), true);
});

test("roleHasPermission: manager can be denied manageReservations via an explicit override map — the resolver never hardcodes 'manager always passes'", () => {
  const revokedFromManager = {
    ...DEFAULT_STAFF_ROLE_PERMISSIONS,
    manager: [] as const,
  };
  assert.strictEqual(roleHasPermission("manager", "manageReservations", revokedFromManager), false);
});

// Faz R.3A D2 — manageBranch, mirroring lib/features/pos/domain/authorization/
// role_permission_map.dart's RolePermissionMap exactly: manager/admin/
// tenantOwner tier (same tier manageReservations already occupies), never
// staff/courier.

test("roleHasPermission: manager has manageBranch under the default mapping — mirrors Dart RolePermissionMap's manager tier", () => {
  assert.strictEqual(roleHasPermission("manager", "manageBranch"), true);
});

test("roleHasPermission: admin has manageBranch under the default mapping", () => {
  assert.strictEqual(roleHasPermission("admin", "manageBranch"), true);
});

test("roleHasPermission: tenantOwner has manageBranch under the default mapping", () => {
  assert.strictEqual(roleHasPermission("tenantOwner", "manageBranch"), true);
});

test("roleHasPermission: base staff does NOT have manageBranch under the default mapping — matches Dart, which never grants branch-level configuration below manager", () => {
  assert.strictEqual(roleHasPermission("staff", "manageBranch"), false);
});

test("roleHasPermission: courier does NOT have manageBranch under the default mapping", () => {
  assert.strictEqual(roleHasPermission("courier", "manageBranch"), false);
});

test("roleHasPermission: manageBranch and manageReservations are genuinely independent checks — a role granted only one via an explicit override does not implicitly gain the other (proves no accidental permission-conflation between the two Faz R.3A siblings)", () => {
  const branchOnly = {
    ...DEFAULT_STAFF_ROLE_PERMISSIONS,
    manager: ["manageBranch"] as const,
  };
  assert.strictEqual(roleHasPermission("manager", "manageBranch", branchOnly), true);
  assert.strictEqual(roleHasPermission("manager", "manageReservations", branchOnly), false);

  const reservationsOnly = {
    ...DEFAULT_STAFF_ROLE_PERMISSIONS,
    manager: ["manageReservations"] as const,
  };
  assert.strictEqual(roleHasPermission("manager", "manageReservations", reservationsOnly), true);
  assert.strictEqual(roleHasPermission("manager", "manageBranch", reservationsOnly), false);
});

// Profile P.4.2B2 — moderateCustomerPhotos, mirroring Dart RolePermissionMap's
// own _managerTier placement for PosAuthorizedAction.moderateCustomerPhoto
// exactly: manager/admin/tenantOwner, never staff/courier.

test("roleHasPermission: manager has moderateCustomerPhotos under the default mapping — mirrors Dart RolePermissionMap's manager tier", () => {
  assert.strictEqual(roleHasPermission("manager", "moderateCustomerPhotos"), true);
});

test("roleHasPermission: admin has moderateCustomerPhotos under the default mapping", () => {
  assert.strictEqual(roleHasPermission("admin", "moderateCustomerPhotos"), true);
});

test("roleHasPermission: tenantOwner has moderateCustomerPhotos under the default mapping", () => {
  assert.strictEqual(roleHasPermission("tenantOwner", "moderateCustomerPhotos"), true);
});

test("roleHasPermission: base staff does NOT have moderateCustomerPhotos under the default mapping", () => {
  assert.strictEqual(roleHasPermission("staff", "moderateCustomerPhotos"), false);
});

test("roleHasPermission: courier does NOT have moderateCustomerPhotos under the default mapping", () => {
  assert.strictEqual(roleHasPermission("courier", "moderateCustomerPhotos"), false);
});

// =======================================================================
// Boncuk Loyalty P4-C-C-B (2026-08-22) — manageTakeawayOrders /
// manageTakeawayOrderCancellations, and the two new authorization
// primitives (requireStaffPermission/requireBranchAccess) exercised
// directly via a hand-built fake CallableRequest (both only ever read
// request.auth.token — no Firestore/Auth I/O needed here; their real,
// end-to-end correctness against genuine custom claims is additionally
// exercised by takeawayOrderLifecycle.test.ts's own emulator-backed
// callable tests). Explicit regression coverage for the "staff must gain
// ONLY manageTakeawayOrders, never any pre-existing manager-tier
// permission" instruction.
// =======================================================================

const ALL_PRE_EXISTING_PERMISSIONS: readonly StaffPermission[] = [
  "manageReservations",
  "manageBranch",
  "manageStaffAccounts",
  "manageStaffAdminRole",
  "manageStaffRoles",
  "manageStaffBranchAccess",
  "moderateCustomerPhotos",
];

test("staff role has EXACTLY manageTakeawayOrders, manageDeliveryOrders, manageDineInOrders, requestDeviceRegistration, viewTenantCustomerDirectory, processPayments, manageCashSessions, manageKitchenOperations, and recordStockCount — Boncuk Loyalty P7-D.1 (2026-08-24) added manageDineInOrders to staff's default grant alongside its existing takeaway/delivery permissions (was previously ['manageTakeawayOrders', 'manageDeliveryOrders'] only, before the dine-in lifecycle existed); AP-2 Stage B (2026-08-26) added requestDeviceRegistration; AP-4 Wave A (payment/cash engine) added processPayments and manageCashSessions — the cashier-tier operational actions, never the manager-tier approve/reconcile counterparts; AP-5 Sprint 1 added manageKitchenOperations; AP-5 Sprint 3 added recordStockCount, mirroring the front-line count action already staff-tier client-side", () => {
  assert.deepStrictEqual(DEFAULT_STAFF_ROLE_PERMISSIONS.staff, [
    "manageTakeawayOrders",
    "manageDeliveryOrders",
    "manageDineInOrders",
    // AP-2 Stage B (2026-08-26) — a line staff member may request a device
    // be registered (they physically set up POS/KDS terminals), but may
    // never approve their own request; approveDeviceRegistration/
    // manageDevices remain manager-tier-and-above only.
    "requestDeviceRegistration",
    // AP-3 continuation (Customer Directory) — day-to-day operational
    // lookup (list/detail/POS search), same reasoning as
    // `manageDineInOrders` itself; the MUTATION permission
    // (`manageTenantCustomerRestriction`) remains manager-tier-and-above
    // only, mirroring `requestDeviceRegistration`/`approveDeviceRegistration`'s
    // own request-vs-approve split.
    "viewTenantCustomerDirectory",
    // AP-4 Wave A — a cashier collects tenders and opens/manages their own
    // cash session day-to-day; approving a refund (approvePaymentRefund),
    // approving a cash-count discrepancy (approveCashReconciliation), and
    // managing fiscal devices (manageFiscalDevices) all remain
    // manager-tier-and-above only, mirroring the request-vs-approve split
    // already established above.
    "processPayments",
    "manageCashSessions",
    // AP-5 Sprint 1 — mirrors the kitchen actions already staff-tier
    // client-side (`PosAuthorizedAction.acknowledgeKitchenItem`/etc.,
    // `role_permission_map.dart`).
    "manageKitchenOperations",
    // AP-5 Sprint 3 — staff-tier, mirrors `PosAuthorizedAction
    // .recordStockCount` exactly (front-line count/waste recording;
    // approving a resulting adjustment stays manager-tier).
    "recordStockCount",
  ]);
});

test("staff role does NOT have manageTakeawayOrderCancellations", () => {
  assert.strictEqual(roleHasPermission("staff", "manageTakeawayOrderCancellations"), false);
});

test("staff role does not gain any pre-existing manager-tier permission as a side effect of the new grant", () => {
  for (const permission of ALL_PRE_EXISTING_PERMISSIONS) {
    assert.strictEqual(
      roleHasPermission("staff", permission),
      false,
      `staff must not have ${permission}`,
    );
  }
});

test("manager/admin/tenantOwner all have BOTH new takeaway permissions", () => {
  for (const role of ["manager", "admin", "tenantOwner"]) {
    assert.strictEqual(roleHasPermission(role, "manageTakeawayOrders"), true, `${role} should have manageTakeawayOrders`);
    assert.strictEqual(
      roleHasPermission(role, "manageTakeawayOrderCancellations"),
      true,
      `${role} should have manageTakeawayOrderCancellations`,
    );
  }
});

test("courier role has no entry at all in the permission map -> zero permissions, including the new takeaway ones", () => {
  assert.strictEqual(DEFAULT_STAFF_ROLE_PERMISSIONS.courier, undefined);
  assert.strictEqual(roleHasPermission("courier", "manageTakeawayOrders"), false);
  assert.strictEqual(roleHasPermission("courier", "manageTakeawayOrderCancellations"), false);
});

// =======================================================================
// Boncuk Loyalty P4-D-B (2026-08-22) — manageTakeawayOrderRefunds. Its own
// dedicated permission, deliberately its own manager+-only tier — never
// granted to staff (unlike manageTakeawayOrders) and never granted to
// courier. Mirrors the manageTakeawayOrderCancellations coverage above
// exactly, one permission over.
// =======================================================================

test("staff role does NOT have manageTakeawayOrderRefunds", () => {
  assert.strictEqual(roleHasPermission("staff", "manageTakeawayOrderRefunds"), false);
});

test("staff role has EXACTLY manageTakeawayOrders, manageDeliveryOrders, manageDineInOrders, requestDeviceRegistration, viewTenantCustomerDirectory, processPayments, manageCashSessions, manageKitchenOperations, and recordStockCount — re-asserted here to prove manageTakeawayOrderRefunds was not silently added to staff's grant (see the P7-D.1/AP-2/AP-4/AP-5 corrections above for the expected set)", () => {
  assert.deepStrictEqual(DEFAULT_STAFF_ROLE_PERMISSIONS.staff, [
    "manageTakeawayOrders",
    "manageDeliveryOrders",
    "manageDineInOrders",
    // AP-2 Stage B (2026-08-26) — a line staff member may request a device
    // be registered (they physically set up POS/KDS terminals), but may
    // never approve their own request; approveDeviceRegistration/
    // manageDevices remain manager-tier-and-above only.
    "requestDeviceRegistration",
    // AP-3 continuation (Customer Directory) — day-to-day operational
    // lookup (list/detail/POS search), same reasoning as
    // `manageDineInOrders` itself; the MUTATION permission
    // (`manageTenantCustomerRestriction`) remains manager-tier-and-above
    // only, mirroring `requestDeviceRegistration`/`approveDeviceRegistration`'s
    // own request-vs-approve split.
    "viewTenantCustomerDirectory",
    // AP-4 Wave A — see the corresponding comment on the test above.
    "processPayments",
    "manageCashSessions",
    // AP-5 Sprint 1 — see the corresponding comment on the test above.
    "manageKitchenOperations",
    // AP-5 Sprint 3 — staff-tier, mirrors `PosAuthorizedAction
    // .recordStockCount` exactly (front-line count/waste recording;
    // approving a resulting adjustment stays manager-tier).
    "recordStockCount",
  ]);
});

test("manager/admin/tenantOwner all have manageTakeawayOrderRefunds under the default mapping", () => {
  for (const role of ["manager", "admin", "tenantOwner"]) {
    assert.strictEqual(
      roleHasPermission(role, "manageTakeawayOrderRefunds"),
      true,
      `${role} should have manageTakeawayOrderRefunds`,
    );
  }
});

test("courier role does NOT have manageTakeawayOrderRefunds", () => {
  assert.strictEqual(roleHasPermission("courier", "manageTakeawayOrderRefunds"), false);
});

test("granting manageTakeawayOrderRefunds does not implicitly grant any pre-existing manager-tier permission or the other takeaway permissions to staff — no accidental escalation", () => {
  for (const permission of [...ALL_PRE_EXISTING_PERMISSIONS, "manageTakeawayOrderCancellations" as const]) {
    assert.strictEqual(
      roleHasPermission("staff", permission),
      false,
      `staff must not have ${permission}`,
    );
  }
});

// =======================================================================
// Boncuk Loyalty P5-B (2026-08-24) — manageDeliveryOrders /
// manageDeliveryOrderCancellations / manageDeliveryOrderRefunds, the
// delivery-channel analogues of the three manageTakeawayOrder* permissions
// above, each its OWN separate permission (never reused from the takeaway
// set). Mirrors the takeaway coverage above exactly, one channel over.
// =======================================================================

test("staff role HAS manageDeliveryOrders under the default mapping — day-to-day operational volume, same reasoning as manageTakeawayOrders", () => {
  assert.strictEqual(roleHasPermission("staff", "manageDeliveryOrders"), true);
});

test("staff role does NOT have manageDeliveryOrderCancellations", () => {
  assert.strictEqual(roleHasPermission("staff", "manageDeliveryOrderCancellations"), false);
});

test("staff role does NOT have manageDeliveryOrderRefunds", () => {
  assert.strictEqual(roleHasPermission("staff", "manageDeliveryOrderRefunds"), false);
});

test("manageDeliveryOrders and manageTakeawayOrders are genuinely independent grants — a role granted only one via an explicit override does not implicitly gain the other (delivery/takeaway staff scoping must never leak into each other)", () => {
  const deliveryOnly = {
    ...DEFAULT_STAFF_ROLE_PERMISSIONS,
    staff: ["manageDeliveryOrders"] as const,
  };
  assert.strictEqual(roleHasPermission("staff", "manageDeliveryOrders", deliveryOnly), true);
  assert.strictEqual(roleHasPermission("staff", "manageTakeawayOrders", deliveryOnly), false);

  const takeawayOnly = {
    ...DEFAULT_STAFF_ROLE_PERMISSIONS,
    staff: ["manageTakeawayOrders"] as const,
  };
  assert.strictEqual(roleHasPermission("staff", "manageTakeawayOrders", takeawayOnly), true);
  assert.strictEqual(roleHasPermission("staff", "manageDeliveryOrders", takeawayOnly), false);
});

test("manager/admin/tenantOwner all have ALL THREE new delivery permissions under the default mapping", () => {
  for (const role of ["manager", "admin", "tenantOwner"]) {
    assert.strictEqual(roleHasPermission(role, "manageDeliveryOrders"), true, `${role} should have manageDeliveryOrders`);
    assert.strictEqual(
      roleHasPermission(role, "manageDeliveryOrderCancellations"),
      true,
      `${role} should have manageDeliveryOrderCancellations`,
    );
    assert.strictEqual(
      roleHasPermission(role, "manageDeliveryOrderRefunds"),
      true,
      `${role} should have manageDeliveryOrderRefunds`,
    );
  }
});

test("courier role has NONE of the three new delivery permissions — deliberately deferred (courier-authoritative delivery completion is out of scope this phase)", () => {
  assert.strictEqual(roleHasPermission("courier", "manageDeliveryOrders"), false);
  assert.strictEqual(roleHasPermission("courier", "manageDeliveryOrderCancellations"), false);
  assert.strictEqual(roleHasPermission("courier", "manageDeliveryOrderRefunds"), false);
});

test("granting the delivery permissions does not implicitly grant any pre-existing manager-tier permission, or any takeaway permission, to staff — no accidental cross-channel or cross-tier escalation", () => {
  for (const permission of [
    ...ALL_PRE_EXISTING_PERMISSIONS,
    "manageTakeawayOrderCancellations" as const,
    "manageTakeawayOrderRefunds" as const,
    "manageDeliveryOrderCancellations" as const,
    "manageDeliveryOrderRefunds" as const,
  ]) {
    assert.strictEqual(
      roleHasPermission("staff", permission),
      false,
      `staff must not have ${permission}`,
    );
  }
});

test("requireStaffPermission: staff role WITH manageDeliveryOrders -> succeeds", async () => {
  const req = fakeRequest({ token: { organizationAccess: ["org-1"], roles: { "org-1": ["staff"] } } });
  await assert.doesNotReject(requireStaffPermission(req, "org-1", "manageDeliveryOrders", neverRevoked));
});

test("requireStaffPermission: staff role lacks manageDeliveryOrderCancellations -> permission-denied", async () => {
  const req = fakeRequest({ token: { organizationAccess: ["org-1"], roles: { "org-1": ["staff"] } } });
  await rejectsWithCode(requireStaffPermission(req, "org-1", "manageDeliveryOrderCancellations", neverRevoked), "permission-denied");
});

test("requireStaffPermission: manager role WITH manageDeliveryOrderRefunds -> succeeds", async () => {
  const req = fakeRequest({ token: { organizationAccess: ["org-1"], roles: { "org-1": ["manager"] } } });
  await assert.doesNotReject(requireStaffPermission(req, "org-1", "manageDeliveryOrderRefunds", neverRevoked));
});

// -----------------------------------------------------------------------
// requireStaffPermission — pure, fake-request tests. Both functions are
// `async` and Firestore-backed by default (ADR-050's claims-revocation
// check) — every call here injects [neverRevoked] as the fourth
// (`claimsRevocationLookup`) argument so this file stays Firestore-free
// and fast, exactly as it was before ADR-050. The real, Firestore-backed
// default lookup is proven separately under the emulator (see
// `claimsRevocationLookup.test.ts`).
// -----------------------------------------------------------------------

function fakeRequest(auth: null | { uid?: string; token: Record<string, unknown> }): CallableRequest {
  return {
    auth: auth
      ? { uid: auth.uid ?? "fake-uid", token: { iat: Math.floor(Date.now() / 1000), ...auth.token } }
      : null,
    data: {},
  } as unknown as CallableRequest;
}

/** Always resolves "never revoked" — the fake [ClaimsRevocationLookup] every test in this file injects to stay Firestore-free. */
const neverRevoked = async (): Promise<number | null> => null;

async function rejectsWithCode(promise: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(promise, (err: unknown) => (err as { code?: string }).code === code);
}

test("requireStaffPermission: no auth -> unauthenticated", async () => {
  await rejectsWithCode(requireStaffPermission(fakeRequest(null), "org-1", "manageTakeawayOrders", neverRevoked), "unauthenticated");
});

test("requireStaffPermission: no organizationAccess for this org -> permission-denied", async () => {
  const req = fakeRequest({ token: { organizationAccess: [], roles: {} } });
  await rejectsWithCode(requireStaffPermission(req, "org-1", "manageTakeawayOrders", neverRevoked), "permission-denied");
});

test("requireStaffPermission: org member but role lacks the requested permission -> permission-denied", async () => {
  const req = fakeRequest({ token: { organizationAccess: ["org-1"], roles: { "org-1": ["staff"] } } });
  await rejectsWithCode(requireStaffPermission(req, "org-1", "manageTakeawayOrderCancellations", neverRevoked), "permission-denied");
});

test("requireStaffPermission: staff role WITH manageTakeawayOrders -> succeeds", async () => {
  const req = fakeRequest({ token: { organizationAccess: ["org-1"], roles: { "org-1": ["staff"] } } });
  await assert.doesNotReject(requireStaffPermission(req, "org-1", "manageTakeawayOrders", neverRevoked));
});

test("requireStaffPermission: role claim for a DIFFERENT organization never leaks authority into this one", async () => {
  const req = fakeRequest({
    token: { organizationAccess: ["org-2"], roles: { "org-2": ["admin"] } },
  });
  await rejectsWithCode(requireStaffPermission(req, "org-1", "manageTakeawayOrders", neverRevoked), "permission-denied");
});

// -----------------------------------------------------------------------
// requireBranchAccess — pure, fake-request tests, mirroring
// firestore.rules' hasBranchAccess exactly.
// -----------------------------------------------------------------------

test("requireBranchAccess: no auth -> unauthenticated", async () => {
  await rejectsWithCode(requireBranchAccess(fakeRequest(null), "org-1", "branch-1", neverRevoked), "unauthenticated");
});

test("requireBranchAccess: branch not present in the claim array -> permission-denied", async () => {
  const req = fakeRequest({ token: { branchAccess: { "org-1": ["branch-2"] } } });
  await rejectsWithCode(requireBranchAccess(req, "org-1", "branch-1", neverRevoked), "permission-denied");
});

test("requireBranchAccess: branch present -> succeeds", async () => {
  const req = fakeRequest({ token: { branchAccess: { "org-1": ["branch-1"] } } });
  await assert.doesNotReject(requireBranchAccess(req, "org-1", "branch-1", neverRevoked));
});

test("requireBranchAccess: a branch grant recorded under a DIFFERENT organization never leaks across tenants", async () => {
  const req = fakeRequest({ token: { branchAccess: { "org-2": ["branch-1"] } } });
  await rejectsWithCode(requireBranchAccess(req, "org-1", "branch-1", neverRevoked), "permission-denied");
});

test("requireBranchAccess: missing branchAccess claim key entirely -> permission-denied, fails closed", async () => {
  const req = fakeRequest({ token: {} });
  await rejectsWithCode(requireBranchAccess(req, "org-1", "branch-1", neverRevoked), "permission-denied");
});

test("requireBranchAccess: malformed (non-array) branchAccess value -> permission-denied, fails closed", async () => {
  const req = fakeRequest({ token: { branchAccess: { "org-1": "branch-1" } } });
  await rejectsWithCode(requireBranchAccess(req, "org-1", "branch-1", neverRevoked), "permission-denied");
});

// -----------------------------------------------------------------------
// ADR-050 — claims-revocation staleness check (`rejectIfClaimsStale`,
// exercised here only through the public functions' injected
// [ClaimsRevocationLookup] parameter, never Firestore).
// -----------------------------------------------------------------------

test("requireStaffPermission: a token issued BEFORE the recorded revocation is rejected, even though its baked-in claims would otherwise pass", async () => {
  const nowMs = Date.now();
  const req = fakeRequest({
    token: {
      iat: Math.floor((nowMs - 10_000) / 1000),
      organizationAccess: ["org-1"],
      roles: { "org-1": ["admin"] },
    },
  });
  const revokedAfterTokenWasIssued = async () => nowMs;
  await rejectsWithCode(
    requireStaffPermission(req, "org-1", "manageStaffAccounts", revokedAfterTokenWasIssued),
    "permission-denied",
  );
});

test("requireStaffPermission: a token issued AFTER the recorded revocation succeeds — it already carries the corrected claims", async () => {
  const nowMs = Date.now();
  const req = fakeRequest({
    token: {
      iat: Math.floor((nowMs + 10_000) / 1000),
      organizationAccess: ["org-1"],
      roles: { "org-1": ["admin"] },
    },
  });
  const revokedBeforeTokenWasIssued = async () => nowMs;
  await assert.doesNotReject(
    requireStaffPermission(req, "org-1", "manageStaffAccounts", revokedBeforeTokenWasIssued),
  );
});

test("requireBranchAccess: a token issued BEFORE the recorded revocation is rejected", async () => {
  const nowMs = Date.now();
  const req = fakeRequest({
    token: { iat: Math.floor((nowMs - 10_000) / 1000), branchAccess: { "org-1": ["branch-1"] } },
  });
  const revokedAfterTokenWasIssued = async () => nowMs;
  await rejectsWithCode(
    requireBranchAccess(req, "org-1", "branch-1", revokedAfterTokenWasIssued),
    "permission-denied",
  );
});

test("requireStaffPermission: no revocation ever recorded for this uid (lookup resolves null) -> never rejected on staleness grounds", async () => {
  const req = fakeRequest({ token: { organizationAccess: ["org-1"], roles: { "org-1": ["admin"] } } });
  await assert.doesNotReject(requireStaffPermission(req, "org-1", "manageStaffAccounts", neverRevoked));
});
