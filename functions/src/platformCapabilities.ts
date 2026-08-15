import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";

/**
 * Server-controlled capability model for platform-level actors —
 * introduced to close a FRAUD-F.0 architect-review finding: precise-
 * evidence-reading callables must depend on a named CAPABILITY, never
 * directly on a `platformRole` literal, so that granting the same
 * capability to a future dedicated identity (e.g. a fraud investigator)
 * never requires touching the callable or the storage/rules architecture
 * — only the mapping in this one file.
 *
 * Sits alongside `platformAuthorization.ts` (same platform-claim
 * namespace, same `isPlatformRole`/`isPlatformMember` "zero shared types
 * with the tenant stack" design as `firestore.rules`) rather than under
 * `fraud/`, since capabilities are a general platform-authorization
 * concept — `fraudEvidence.readPrecise` is simply the first one.
 *
 * Deliberately NOT a new Firebase custom claim: a capability is derived,
 * server-side, from the existing trusted `platformRole` claim at check
 * time — a pure function, nothing new to keep in sync with a claims-sync
 * Cloud Function (of which none exists for `platformRole` in this
 * codebase today — see `platformAuthorization.ts`'s own doc comment). A
 * capability is never read from, or influenced by, `request.data` — only
 * `request.auth.token`, exactly like `requirePlatformMember`.
 */

export type PlatformCapability = "fraudEvidence.readPrecise";

type KnownPlatformRole = "platformOwner" | "platformAdministrator";

/**
 * The single source of truth for which capabilities each platformRole
 * carries. Extending this map is the ONLY change needed to grant an
 * existing role a new capability, or to widen an existing capability's
 * grant — no caller of `hasPlatformCapability`/`requirePlatformCapability`
 * ever needs to change.
 */
const CAPABILITIES_BY_PLATFORM_ROLE: Record<
  KnownPlatformRole,
  ReadonlySet<PlatformCapability>
> = {
  platformOwner: new Set<PlatformCapability>(["fraudEvidence.readPrecise"]),
  platformAdministrator: new Set<PlatformCapability>(),
};

function isKnownPlatformRole(value: unknown): value is KnownPlatformRole {
  return value === "platformOwner" || value === "platformAdministrator";
}

/**
 * Capabilities are a platform-level concept only — a tenant `roles`/
 * `organizationAccess` claim, a courier identity, or an ordinary customer
 * (no `platformRole` claim at all) never resolves to any capability,
 * regardless of how senior within its own tenant it is.
 */
export function capabilitiesForPlatformRole(
  platformRole: unknown,
): ReadonlySet<PlatformCapability> {
  if (!isKnownPlatformRole(platformRole)) {
    return new Set();
  }
  return CAPABILITIES_BY_PLATFORM_ROLE[platformRole];
}

/**
 * Reads the caller's capabilities from their own trusted, server-verified
 * `request.auth.token.platformRole` — never from `request.data`, which a
 * client fully controls and which must never influence an authorization
 * decision.
 */
export function hasPlatformCapability(
  request: CallableRequest,
  capability: PlatformCapability,
): boolean {
  if (!request.auth) return false;
  const platformRole = request.auth.token?.platformRole;
  return capabilitiesForPlatformRole(platformRole).has(capability);
}

export function requirePlatformCapability(
  request: CallableRequest,
  capability: PlatformCapability,
): void {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  if (!hasPlatformCapability(request, capability)) {
    throw new HttpsError(
      "permission-denied",
      `The "${capability}" capability is required.`,
    );
  }
}
