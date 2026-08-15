import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";

/**
 * Server-side mirror of `firestore.rules`'s `isPlatformMember()` — Faz D.1
 * (Canonical Restaurant/Branch Provisioning, Gel Al architecture analysis).
 * Both places must agree on what counts as a platform-level actor: a
 * `platformRole` custom claim of `'platformOwner'` or
 * `'platformAdministrator'` — the same separate claim namespace
 * `firestore.rules` already documents as having "zero shared types with
 * the tenant stack" (ADR-025). Tenant `roles`/`organizationAccess` claims
 * are deliberately never checked here: provisioning a restaurant/branch is
 * tenant-*onboarding*, a platform-level action, not something any tenant
 * role (however senior within one tenant) is authorized to do — mirrors
 * why `restaurants`/`branches` have no client write path of any kind in
 * `firestore.rules`, not even for an org member.
 *
 * Custom claims are not yet synced by any deployed Cloud Function
 * (`docs/firestore_data_model.md`'s own admission — the `memberships` ->
 * claims sync Function is still Sprint 9F, undeployed) — until it exists,
 * a platform-role claim must be set manually (Admin SDK
 * `setCustomUserClaims`) for any real platform actor, exactly as every
 * emulator test and the dev seed script (`scripts/seed_dev_tenant.mjs`)
 * do.
 */
export function requirePlatformMember(request: CallableRequest): void {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const role = request.auth.token?.platformRole;
  if (role !== "platformOwner" && role !== "platformAdministrator") {
    throw new HttpsError(
      "permission-denied",
      "Platform Owner or Platform Administrator authorization is required.",
    );
  }
}
