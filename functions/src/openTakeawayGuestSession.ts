import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { resolveTakeawayQrTokenInternal } from "./takeawayQrTokenResolution";
import {
  TAKEAWAY_GUEST_SESSION_STATUS,
  TAKEAWAY_GUEST_SESSION_TTL_MS,
} from "./takeawayGuestSessionConfig";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * Creates (or reuses) a server-authoritative `takeawayGuestSessions`
 * record for a kasadaki Gel Al QR scan — Faz D.2. Mirrors
 * `openTableGuestSession`'s critical security property exactly: the only
 * client input is the opaque QR [token] itself — organization/
 * restaurant/branch identity is always re-derived server-side via
 * [resolveTakeawayQrTokenInternal] against the real Faz D.1/D.1.1
 * canonical chain, never accepted as a caller-supplied argument, and
 * never trusted from a prior `resolveTakeawayQrToken` preview call.
 *
 * Requires the caller to already be signed in ([request.auth] non-null) —
 * anonymous sign-in satisfies this, and so does an already-real
 * (phone-verified) session; this function does not care which, and never
 * creates a `customers/{uid}` document, touches CRM, or grants loyalty —
 * [request.auth.uid] becomes `guestAuthUid` and nothing else. (Whether a
 * client reuses an existing real session or signs in anonymously is
 * `TechnicalIdentityProvider.ensureSignedIn()`'s existing, unchanged
 * responsibility on the Flutter side — not wired to this function this
 * phase, per direct instruction; this function's own contract already
 * supports either case without modification.)
 *
 * **Idempotency (§10)**: before minting a new session, this function
 * looks for an existing *active, unexpired* session already owned by
 * this exact (`guestAuthUid`, `qrTokenId`) pair and reuses it instead —
 * a double-tap or retry against the same QR by the same caller never
 * spawns a second session. Scoped to the caller's own uid (not the QR
 * token alone), so a *different* customer scanning the same physical QR
 * always gets their own independent session — reuse never crosses
 * callers. The query is two plain equality filters
 * (`guestAuthUid`/`qrTokenId`) with the `status`/`expiresAt` check done
 * in memory afterward, deliberately avoiding a composite-index
 * requirement for a query this codebase has no existing index-management
 * process for yet.
 *
 * Fails closed on every non-`valid` resolution (`notFound`/`invalid`/
 * `expired`) — no session document is ever written for a bad token,
 * including one that has since been revoked/rotated/expired (new-session
 * creation is where revocation actually takes effect — see
 * `takeawayGuestSessionConfig.ts`'s own doc comment on why an
 * already-open session is not retroactively affected).
 *
 * Session lifetime comes from `takeawayGuestSessionConfig.ts`'s
 * `TAKEAWAY_GUEST_SESSION_TTL_MS` — never a bare number here, and never
 * client-influenced.
 *
 * App Check-ready (Faz D.3 §15) via `appCheckConfig.ts`'s
 * `shouldEnforceAppCheck()`, same deployment-env-var activation as
 * `resolveTakeawayQrToken` — defense-in-depth on top of the
 * authentication requirement already above, off by default in
 * emulator/dev.
 */
export const openTakeawayGuestSession = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Sign-in (anonymous is sufficient) is required.",
    );
  }

  const token = request.data?.token;
  if (typeof token !== "string" || token.length === 0) {
    throw new HttpsError("invalid-argument", "token is required.");
  }

  const resolution = await resolveTakeawayQrTokenInternal(token);
  if (resolution.validityStatus === "notFound") {
    throw new HttpsError("not-found", "QR code not recognized.");
  }
  if (resolution.validityStatus !== "valid") {
    throw new HttpsError(
      "failed-precondition",
      `QR code is ${resolution.validityStatus}.`,
    );
  }

  const db = getFirestore();
  const uid = request.auth.uid;
  const qrTokenId = resolution.qrCodeId!;
  const now = new Date();

  const existingSnapshot = await db
    .collection("takeawayGuestSessions")
    .where("guestAuthUid", "==", uid)
    .where("qrTokenId", "==", qrTokenId)
    .get();
  for (const existingDoc of existingSnapshot.docs) {
    const data = existingDoc.data();
    if (data.status !== TAKEAWAY_GUEST_SESSION_STATUS.active) continue;
    const rawExpiresAt = data.expiresAt;
    const expiresAt: Date | null =
      typeof rawExpiresAt?.toDate === "function" ? rawExpiresAt.toDate() : rawExpiresAt ?? null;
    if (expiresAt !== null && expiresAt.getTime() > now.getTime()) {
      return {
        sessionId: existingDoc.id,
        organizationId: data.organizationId,
        restaurantId: data.restaurantId,
        branchId: data.branchId,
        branchDisplayName: resolution.branchDisplayName,
        expiresAt: expiresAt.toISOString(),
        reused: true,
      };
    }
  }

  const expiresAt = new Date(now.getTime() + TAKEAWAY_GUEST_SESSION_TTL_MS);
  const sessionRef = db.collection("takeawayGuestSessions").doc();

  await sessionRef.set({
    organizationId: resolution.organizationId,
    restaurantId: resolution.restaurantId,
    branchId: resolution.branchId,
    guestAuthUid: uid,
    status: TAKEAWAY_GUEST_SESSION_STATUS.active,
    createdAt: now,
    expiresAt,
    lastActivityAt: now,
    qrTokenId,
  });

  return {
    sessionId: sessionRef.id,
    organizationId: resolution.organizationId,
    restaurantId: resolution.restaurantId,
    branchId: resolution.branchId,
    branchDisplayName: resolution.branchDisplayName,
    expiresAt: expiresAt.toISOString(),
    reused: false,
  };
  },
);
