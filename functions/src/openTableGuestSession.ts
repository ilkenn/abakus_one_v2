import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { resolveTableQrTokenInternal } from "./qrTokenResolution";
import {
  TABLE_GUEST_SESSION_STATUS,
  TABLE_GUEST_SESSION_TTL_MS,
} from "./tableGuestSessionConfig";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { activeReservationTableContextRef, readLiveReservationTableContext } from "./reservationTableContext";

/**
 * Creates a server-authoritative `tableGuestSessions` record for a QR
 * table visit — Table Guest Session Phase 1/2 (docs/decisions.md, Table
 * Guest Session architecture; approved Decision Review: Firebase Anonymous
 * Auth as the technical identity layer, never a normal Abaküs customer
 * account — no `customers/{uid}` document is ever created or touched by
 * this function).
 *
 * **Critical security property**: the only client input is the opaque QR
 * [token] itself — organization/restaurant/branch/table identity is
 * always re-derived server-side via [resolveTableQrTokenInternal], never
 * accepted as a caller-supplied argument. A client that already knows
 * (from a prior `resolveTableQrToken` preview call) an organization/
 * branch/table id cannot use those ids to open a session for a table it
 * never actually scanned — every call independently re-validates the raw
 * token.
 *
 * Requires the caller to already be signed in ([request.auth] non-null) —
 * anonymous sign-in satisfies this. [request.auth.uid] becomes
 * `guestAuthUid`, the one identity a Firestore Security Rule can verify
 * ownership against later (Phase 3) — never a client-supplied uid.
 *
 * Fails closed on every non-`valid` resolution (`notFound`/`invalid`/
 * `expired`) — no session document is ever written for a bad token.
 *
 * Session lifetime comes from `tableGuestSessionConfig.ts`'s
 * `TABLE_GUEST_SESSION_TTL_MS` (currently 6 hours; see that file's own
 * doc comment for why, and for the environment-variable override) — never
 * a bare number here, and never client-influenced.
 *
 * **App Check (Faz D.3.2)** via `appCheckConfig.ts`'s
 * `shouldEnforceAppCheck()` — the exact same shared config the takeaway
 * analogue (`openTakeawayGuestSession`) already uses, not a second,
 * parallel system. This is defense-in-depth layered on top of the
 * authentication requirement above, not a replacement for it: App Check
 * proves the request comes from a genuine build of this app, never who
 * the caller is — the two mechanisms stay independent, and the
 * `unauthenticated` check below is completely unchanged. Off by default
 * in every emulator/local-dev run, same activation switch
 * (`ENFORCE_APP_CHECK=true` on the deployed runtime) as every other App
 * Check-ready Function in this codebase.
 */
export const openTableGuestSession = onCall(
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

  const resolution = await resolveTableQrTokenInternal(token);
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
  const now = new Date();
  const expiresAt = new Date(now.getTime() + TABLE_GUEST_SESSION_TTL_MS);

  // Faz R.1C.2 §11/§12 — canonical check order: QR resolve (above, already
  // includes the T-20 protection-bucket deny), *then* read the active
  // reservation table context, *then* create the session. A future
  // reservation's protection window starting is what blocks a *new*
  // session at all (already enforced above); an *existing* open context on
  // an otherwise-unprotected table only ever adds a snapshot to the new
  // session, it never blocks it.
  const liveContext = await readLiveReservationTableContext(
    activeReservationTableContextRef(db, resolution.tableId!),
    now,
  );
  const reservationContextId = liveContext?.reservationId ?? null;

  const sessionRef = db.collection("tableGuestSessions").doc();

  await sessionRef.set({
    organizationId: resolution.organizationId,
    restaurantId: resolution.restaurantId,
    branchId: resolution.branchId,
    tableId: resolution.tableId,
    guestAuthUid: request.auth.uid,
    status: TABLE_GUEST_SESSION_STATUS.active,
    createdAt: now,
    expiresAt: expiresAt,
    lastActivityAt: now,
    qrTokenId: resolution.qrCodeId,
    // Server-generated, immutable snapshot (Faz R.1C.2 §11) — never a
    // client input, never re-derived later. `null` for the ordinary,
    // non-reservation walk-in case.
    reservationContextId,
  });

  return {
    sessionId: sessionRef.id,
    organizationId: resolution.organizationId,
    restaurantId: resolution.restaurantId,
    branchId: resolution.branchId,
    tableId: resolution.tableId,
    tableDisplayName: resolution.tableDisplayName,
    branchDisplayName: resolution.branchDisplayName,
    expiresAt: expiresAt.toISOString(),
    reservationContextId,
  };
  },
);
