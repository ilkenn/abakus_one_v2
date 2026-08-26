import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * AP-2 Stage B, Correction #2 — canonical tenant/branch context
 * resolution. A caller with access to more than one organization/branch
 * cannot have the backend silently pick one for them, but a client-supplied
 * organizationId/branchId is never authorization truth on its own either:
 * it is only ever used as an untrusted LOCATOR to select among the
 * caller's own real, active memberships/branch access — never accepted at
 * face value, never trusted to prove the caller may act there.
 *
 * This replaces `admin_dependencies_provider.dart`'s hardcoded
 * `'org-1'`/`'restaurant-1'`/`'branch-1'` defaults as the AUTHORIZATION
 * source for every AP-2 command — those Dart literals may still exist as
 * UI-convenience seed data (out of this file's scope), but no AP-2 backend
 * command may ever trust a client-sent id without running it through
 * [resolveVerifiedBranchContext] (or the equivalent inline check) first.
 */

export interface VerifiedBranchContext {
  organizationId: string;
  branchId: string;
  restaurantId: string;
  roles: string[];
}

interface MembershipRecord {
  status: string;
  roles: string[];
  branchAccess: string[];
}

interface BranchRecord {
  organizationId?: string;
  restaurantId?: string;
  status?: string;
}

/**
 * Verifies a client-supplied `{organizationId, branchId}` locator against
 * the caller's own durable membership and the real branch→organization
 * chain — fails closed (`permission-denied`/`not-found`/
 * `failed-precondition`) on any mismatch, revoked membership, missing
 * branch access, or inactive branch, rather than silently substituting a
 * different context the caller does have access to.
 */
export async function resolveVerifiedBranchContext(
  request: CallableRequest,
  locator: { organizationId: string; branchId: string },
): Promise<VerifiedBranchContext> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const db = getFirestore();

  const membershipSnap = await db
    .collection("memberships")
    .doc(`${locator.organizationId}_${request.auth.uid}`)
    .get();
  if (!membershipSnap.exists) {
    throw new HttpsError("permission-denied", "No membership exists for the requested organization.");
  }
  const membership = membershipSnap.data() as MembershipRecord;
  if (membership.status !== "active") {
    throw new HttpsError("permission-denied", "This membership is not active.");
  }
  if (!membership.branchAccess.includes(locator.branchId)) {
    throw new HttpsError("permission-denied", "No branch access exists for the requested branch.");
  }

  const branchSnap = await db.collection("branches").doc(locator.branchId).get();
  if (!branchSnap.exists) {
    throw new HttpsError("not-found", "The requested branch no longer exists.");
  }
  const branch = branchSnap.data() as BranchRecord;
  if (branch.organizationId !== locator.organizationId) {
    throw new HttpsError("failed-precondition", "This branch does not belong to the requested organization.");
  }
  if (branch.status === "inactive") {
    throw new HttpsError("failed-precondition", "This branch is inactive.");
  }

  return {
    organizationId: locator.organizationId,
    branchId: locator.branchId,
    restaurantId: branch.restaurantId ?? "",
    roles: membership.roles,
  };
}

/**
 * Read-only, self-derived enumeration of every organization/branch the
 * caller's own ACTIVE memberships actually grant — lets the Flutter client
 * build a real context picker instead of assuming a single hardcoded
 * tenant. Accepts no organizationId input at all; everything is derived
 * from `request.auth.uid`.
 */
export const resolveActorContext = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const db = getFirestore();
    // Mirrors staffMembership.ts's resyncClaimsForUid: query by uid only,
    // filter status in-memory — avoids any composite-index ambiguity and
    // matches the one existing precedent for this exact query shape.
    const snapshot = await db.collection("memberships").where("uid", "==", request.auth.uid).get();

    const organizations = snapshot.docs
      .map((doc) => doc.data() as { organizationId: string; status: string; roles: string[]; branchAccess: string[] })
      .filter((data) => data.status === "active")
      .map((data) => ({
        organizationId: data.organizationId,
        roles: data.roles,
        branchIds: data.branchAccess,
      }));

    return { organizations };
  },
);
