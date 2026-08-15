import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * Faz R.3C.1 — the server-authoritative device-token registration
 * callable, replacing Faz R.3C's direct-client-write registration path for
 * the real Firestore-backed repository.
 *
 * **Why a callable is required, not optional.** R.3C's fix inside the Dart
 * `RegisterDeviceToken` use case (revoke a token found active under a
 * *different* uid, then create a fresh record for the caller) is correct
 * logic — but it cannot actually run against real Firestore from the
 * client. `firestore.rules`'s `deviceTokens` read rule is
 * `resource.data.uid == request.auth.uid`: a customer can only ever read
 * their *own* token documents. A different customer re-registering the
 * same physical token therefore cannot even **see** that the token
 * already belongs to someone else — `findByToken` silently returns
 * nothing usable from their perspective, so the client would simply
 * create a **second** document sharing the same `token` value, leaving
 * both the old and new owner "active" — the exact invariant this fix is
 * required to prevent. Firestore's own per-document security rules have
 * no primitive for "let uid B revoke a record owned by uid A, but only
 * for this one specific reassociation case" — that check can only be
 * made by something that can see across owners, i.e. the Admin SDK.
 *
 * [organizationId] is intentionally never a caller-supplied argument —
 * this app is genuinely single-tenant today (`org-1` is the only
 * organization that exists), and there is no branch/restaurant chain to
 * resolve it from for a token that is not scoped to any particular
 * branch. [SINGLE_TENANT_ORGANIZATION_ID] mirrors the Dart client's own
 * `kSingleTenantOrganizationId` (`lib/core/config/current_organization
 * .dart`) — the identical, disclosed "real multi-tenant resolution is
 * future work" placeholder, kept in exactly one place per side rather
 * than duplicated with drift risk.
 *
 * **Firestore Rules were tightened alongside this callable**:
 * `deviceTokens` `create` is now `if false` (Cloud Function only) — a
 * direct client `create` bypassing this callable would reintroduce the
 * exact duplicate-token-across-owners risk this callable exists to close,
 * since per-document rules cannot dedupe by a field *value* (`token`)
 * across different document IDs, only a server-side transaction across
 * the whole collection can. `read`/`update`/`delete` for a caller's own
 * uid are unchanged — `RevokeDeviceTokensForUser`'s existing logout-time
 * self-revocation continues to work via direct client writes, since that
 * only ever touches a caller's own already-owned documents (no cross-
 * visibility problem exists there).
 */

const SINGLE_TENANT_ORGANIZATION_ID = "org-1";

interface RegisterDeviceTokenResult {
  tokenId: string;
  reused: boolean;
}

export const registerDeviceToken = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<RegisterDeviceTokenResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const uid = request.auth.uid;

    const token = request.data?.token;
    if (typeof token !== "string" || token.length === 0) {
      throw new HttpsError("invalid-argument", "token is required.");
    }
    const platform = request.data?.platform;
    if (typeof platform !== "string" || platform.length === 0) {
      throw new HttpsError("invalid-argument", "platform is required.");
    }

    const db = getFirestore();
    const collection = db.collection("deviceTokens");
    const now = new Date();

    return db.runTransaction(async (tx) => {
      const snapshot = await tx.get(collection.where("token", "==", token));

      let ownRecord: FirebaseFirestore.QueryDocumentSnapshot | null = null;
      const othersToRevoke: FirebaseFirestore.QueryDocumentSnapshot[] = [];
      for (const doc of snapshot.docs) {
        const data = doc.data();
        if (data.revokedAt != null) continue; // already inactive — leave its history alone.
        if (data.uid === uid) {
          ownRecord = doc;
        } else {
          othersToRevoke.push(doc);
        }
      }

      // Faz R.3C.1 — the actual reassociation: a physical token found
      // active under any uid other than the caller's own is revoked here,
      // inside this same transaction, before the caller's own record is
      // resolved/created. This is the exact operation client-side rules
      // structurally cannot perform (see this file's own doc comment).
      // Every matching stale duplicate is revoked, not just the first —
      // defensive against any pre-existing duplicate data, not only the
      // single-duplicate case this fix directly targets.
      for (const doc of othersToRevoke) {
        tx.set(
          doc.ref,
          { revokedAt: now.toISOString(), updatedAt: now.toISOString() },
          { merge: true },
        );
      }

      if (ownRecord) {
        return { tokenId: ownRecord.id, reused: true };
      }

      const newDocRef = collection.doc();
      tx.set(newDocRef, {
        uid,
        organizationId: SINGLE_TENANT_ORGANIZATION_ID,
        token,
        platform,
        registeredAt: now.toISOString(),
        revokedAt: null,
      });
      return { tokenId: newDocRef.id, reused: false };
    });
  },
);
