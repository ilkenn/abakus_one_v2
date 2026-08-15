import { test } from "node:test";
import assert from "node:assert";
import { roleHasPermission, DEFAULT_STAFF_ROLE_PERMISSIONS } from "../staffAuthorization";

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
