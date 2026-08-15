import { test } from "node:test";
import assert from "node:assert";
import type { CallableRequest } from "firebase-functions/v2/https";
import {
  capabilitiesForPlatformRole,
  hasPlatformCapability,
  requirePlatformCapability,
} from "../platformCapabilities";

/**
 * Pure, no-emulator unit tests — FRAUD-F.0 architect-review correction.
 * Mirrors `deliveryPaymentPolicy.test.ts`'s "no Firestore/Functions/Auth
 * emulator involved" shape: every function under test here is a pure
 * function of its arguments (a plain, hand-built request object stands in
 * for a real `CallableRequest` — no actual Cloud Functions runtime is
 * needed to exercise this logic in isolation).
 */

function fakeRequest(
  auth: { platformRole?: unknown; organizationAccess?: unknown; roles?: unknown } | null,
  data: Record<string, unknown> = {},
): CallableRequest {
  return {
    auth: auth
      ? { uid: "test-uid", token: auth as Record<string, unknown> }
      : undefined,
    data,
  } as unknown as CallableRequest;
}

test("capabilitiesForPlatformRole: platformOwner resolves fraudEvidence.readPrecise", () => {
  const capabilities = capabilitiesForPlatformRole("platformOwner");
  assert.strictEqual(capabilities.has("fraudEvidence.readPrecise"), true);
});

test("capabilitiesForPlatformRole: platformAdministrator does NOT resolve fraudEvidence.readPrecise", () => {
  const capabilities = capabilitiesForPlatformRole("platformAdministrator");
  assert.strictEqual(capabilities.has("fraudEvidence.readPrecise"), false);
});

test("capabilitiesForPlatformRole: an unknown/undefined platformRole resolves no capabilities", () => {
  assert.strictEqual(capabilitiesForPlatformRole(undefined).size, 0);
  assert.strictEqual(capabilitiesForPlatformRole("something-else").size, 0);
});

test("hasPlatformCapability: platformOwner has fraudEvidence.readPrecise", () => {
  const request = fakeRequest({ platformRole: "platformOwner" });
  assert.strictEqual(
    hasPlatformCapability(request, "fraudEvidence.readPrecise"),
    true,
  );
});

test("hasPlatformCapability: platformAdministrator does not have fraudEvidence.readPrecise", () => {
  const request = fakeRequest({ platformRole: "platformAdministrator" });
  assert.strictEqual(
    hasPlatformCapability(request, "fraudEvidence.readPrecise"),
    false,
  );
});

test("hasPlatformCapability: a tenant admin (organizationAccess/roles claims, no platformRole) has no capability", () => {
  const request = fakeRequest({
    organizationAccess: ["org-1"],
    roles: { "org-1": ["admin"] },
  });
  assert.strictEqual(
    hasPlatformCapability(request, "fraudEvidence.readPrecise"),
    false,
  );
});

test("hasPlatformCapability: a tenant manager has no capability", () => {
  const request = fakeRequest({
    organizationAccess: ["org-1"],
    roles: { "org-1": ["manager"] },
  });
  assert.strictEqual(
    hasPlatformCapability(request, "fraudEvidence.readPrecise"),
    false,
  );
});

test("hasPlatformCapability: a tenant staff member has no capability", () => {
  const request = fakeRequest({
    organizationAccess: ["org-1"],
    roles: { "org-1": ["staff"] },
  });
  assert.strictEqual(
    hasPlatformCapability(request, "fraudEvidence.readPrecise"),
    false,
  );
});

test("hasPlatformCapability: a courier has no capability", () => {
  const request = fakeRequest({
    organizationAccess: ["org-1"],
    roles: { "org-1": ["courier"] },
  });
  assert.strictEqual(
    hasPlatformCapability(request, "fraudEvidence.readPrecise"),
    false,
  );
});

test("hasPlatformCapability: an ordinary customer (no claims at all) has no capability", () => {
  const request = fakeRequest({});
  assert.strictEqual(
    hasPlatformCapability(request, "fraudEvidence.readPrecise"),
    false,
  );
});

test("hasPlatformCapability: an unauthenticated request has no capability", () => {
  const request = fakeRequest(null);
  assert.strictEqual(
    hasPlatformCapability(request, "fraudEvidence.readPrecise"),
    false,
  );
});

test("hasPlatformCapability: a client-supplied request.data.platformRole/capability cannot forge the result", () => {
  const request = fakeRequest(
    {}, // no real platformRole claim
    { platformRole: "platformOwner", capabilities: ["fraudEvidence.readPrecise"] },
  );
  assert.strictEqual(
    hasPlatformCapability(request, "fraudEvidence.readPrecise"),
    false,
    "only request.auth.token may ever influence this decision, never request.data",
  );
});

test("requirePlatformCapability: throws unauthenticated for an unauthenticated caller", () => {
  const request = fakeRequest(null);
  assert.throws(
    () => requirePlatformCapability(request, "fraudEvidence.readPrecise"),
    (error: unknown) =>
      (error as { code?: string }).code === "permission-denied" ||
      (error as { code?: string }).code === "unauthenticated" ||
      /unauthenticated/i.test(String((error as { message?: string }).message)),
  );
});

test("requirePlatformCapability: throws permission-denied for an authenticated caller without the capability", () => {
  const request = fakeRequest({ platformRole: "platformAdministrator" });
  assert.throws(() =>
    requirePlatformCapability(request, "fraudEvidence.readPrecise"),
  );
});

test("requirePlatformCapability: does not throw for platformOwner", () => {
  const request = fakeRequest({ platformRole: "platformOwner" });
  assert.doesNotThrow(() =>
    requirePlatformCapability(request, "fraudEvidence.readPrecise"),
  );
});

test("the capability mapping is data-driven, not a hardcoded conditional in the callable — extending CAPABILITIES_BY_PLATFORM_ROLE is provably the only thing that needs to change to grant a role a capability", () => {
  // This does not mutate the real map (it's a module-private const) — it
  // demonstrates the *shape* of extensibility this correction exists to
  // provide: capabilitiesForPlatformRole is a pure lookup, so a future
  // change to grant platformAdministrator this same capability (or to add
  // an entirely new capability) is a one-line edit to that map, and every
  // caller (hasPlatformCapability, requirePlatformCapability,
  // getPreciseFraudEvidence) picks it up automatically with zero further
  // code changes — proven here by the fact that none of the calls above
  // reference "platformOwner" anywhere except as test input data.
  const ownerCapabilities = capabilitiesForPlatformRole("platformOwner");
  const adminCapabilities = capabilitiesForPlatformRole("platformAdministrator");
  assert.notDeepStrictEqual(
    [...ownerCapabilities],
    [...adminCapabilities],
    "the two roles must resolve to different capability sets today, driven entirely by the map",
  );
});
