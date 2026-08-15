import { getFirestore } from "firebase-admin/firestore";
import { resolveActiveTakeawayBranch } from "./takeawayScope";

/**
 * Server-side validity vocabulary for a `takeawayQrCodes` token —
 * mirrors `TableQrValidityStatus`'s exact shape (Faz D.2, Gel Al QR +
 * Guest Session Backend). Kept as a hand-mirrored duplication for the
 * same reason `orderStatus.ts`/`qrTokenResolution.ts` mirror their own
 * Dart counterparts — no Dart<->TypeScript code-sharing mechanism exists
 * in this repository, and (per this phase's own explicit instruction) no
 * Dart domain model exists yet for this to mirror anyway — Faz D.2 is
 * backend-only.
 */
export type TakeawayQrValidityStatus = "valid" | "invalid" | "expired" | "notFound";

/** Mirrors `TableQrCodeStatus`'s exact shape — `inactive` doubles as this domain's "revoked" state (see `takeawayGuestSessionConfig.ts`'s own doc comment on why revocation doesn't retroactively kill an already-open session), matching `tableQrCodes`' own existing vocabulary rather than inventing a fifth status value. */
export type TakeawayQrCodeStatus = "active" | "inactive" | "rotated" | "expired";
export const TAKEAWAY_QR_CODE_STATUS: Record<TakeawayQrCodeStatus, TakeawayQrCodeStatus> = {
  active: "active",
  inactive: "inactive",
  rotated: "rotated",
  expired: "expired",
};

/**
 * The full internal resolution — organization/restaurant/branch identity
 * included. Used server-side only (by `openTakeawayGuestSession`, which
 * needs these ids to write a scoped `takeawayGuestSessions` document) —
 * **never returned to a client directly**. See [TakeawayQrPublicPreview]
 * for the one shape a client is ever allowed to see. Deliberately no
 * `tableId` field at all — a takeaway QR belongs directly to a branch,
 * not a table.
 */
export interface TakeawayQrResolution {
  validityStatus: TakeawayQrValidityStatus;
  organizationId?: string;
  restaurantId?: string;
  branchId?: string;
  /** Sourced live from the resolved `branches/{branchId}` document's own `name` field at resolution time, never denormalized/stored on the `takeawayQrCodes` document itself — avoids a second, potentially-stale copy of a value the chain validation already had to fetch anyway. */
  branchDisplayName?: string;
  /** The resolved `takeawayQrCodes` document id — used as `qrTokenId` on the `takeawayGuestSessions` document this resolution authorizes, never returned to the client. */
  qrCodeId?: string;
}

/**
 * The minimized, public-safe shape `resolveTakeawayQrToken` (unauthenticated,
 * callable from a bare QR scan before any session exists) actually
 * returns — mirrors `TableQrPublicPreview`'s exact "no internal ids ever
 * leave the server through this call" contract. `restaurantDisplayName`
 * is deliberately omitted: this app's own customer-facing precedent
 * (Table Guest Session's own preview) already shows only a branch-level
 * name for the exact same "Masa 12 · Abaküs Ortaköy" style confirmation
 * UI, and no additional UI need for a restaurant-level name was
 * identified this phase.
 */
export interface TakeawayQrPublicPreview {
  status: TakeawayQrValidityStatus;
  branchDisplayName?: string;
}

export function toPublicPreview(
  resolution: TakeawayQrResolution,
): TakeawayQrPublicPreview {
  if (resolution.validityStatus !== "valid") {
    return { status: resolution.validityStatus };
  }
  return { status: "valid", branchDisplayName: resolution.branchDisplayName };
}

function toDate(value: unknown): Date | null {
  if (value === null || value === undefined) return null;
  if (typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string | number);
}

/**
 * Resolves an opaque takeaway QR token to organization/restaurant/branch
 * identity, entirely server-side (Admin SDK — bypasses Firestore
 * Security Rules by design, since `takeawayQrCodes` is not
 * client-readable at all; see `firestore.rules`'s fail-closed catch-all).
 * Mirrors `resolveTableQrTokenInternal`'s own two-stage shape (resolve
 * the QR document itself, then resolve what it points at) but goes one
 * layer further: a table QR points at a `restaurantTables` document that
 * already denormalizes its own organization/restaurant/branch identity,
 * while a takeaway QR's `organizationId`/`restaurantId`/`branchId` must
 * be independently verified against the **real, canonical**
 * `organizations`/`restaurants`/`branches` chain Faz D.1/D.1.1 built —
 * exactly the validation this phase's own request (§5) specifies:
 *
 * 1. Unknown token -> `notFound`.
 * 2. A token whose `TakeawayQrCode` is not `active`, or is past its own
 *    `expiresAt` -> `expired` (if the reason is specifically expiry) or
 *    `invalid` (anything else — inactive/rotated).
 * 3. The QR's own `organizationId` doesn't resolve to a real
 *    `organizations` document -> `notFound` (a broken/impossible
 *    reference, not "exists but unusable").
 * 4. That organization exists but `isActive != true` -> `invalid`.
 * 5. The QR's own `restaurantId` doesn't resolve to a real `restaurants`
 *    document, or that restaurant's own `organizationId` doesn't match
 *    the QR's claimed `organizationId` (a broken chain) -> `notFound`.
 * 6. That restaurant exists, correctly chained, but `isActive != true`
 *    -> `invalid`.
 * 7. The QR's own `branchId` doesn't resolve to a real `branches`
 *    document, or that branch's own `restaurantId`/`organizationId`
 *    don't match the QR's claimed chain -> `notFound`.
 * 8. That branch exists, correctly chained, but its `status != 'active'`,
 *    or `emergencyStopped == true`, or `'takeaway' not in
 *    supportedOrderChannelIds` -> `invalid` (the code itself is genuine
 *    and correctly chained, but this specific branch can't accept a
 *    takeaway visit right now).
 * 9. Otherwise -> `valid`.
 *
 * The `notFound` vs `invalid` split throughout mirrors
 * `resolveTableQrTokenInternal`'s own precedent exactly: "doesn't exist /
 * chain is broken" -> `notFound`; "exists, chain is intact, but not
 * currently operational" -> `invalid`.
 *
 * Used by both `resolveTakeawayQrToken` (read-only preview) and
 * `openTakeawayGuestSession` (which independently re-resolves from the
 * raw token rather than trusting a caller-supplied organization/branch id
 * or a prior preview call's result — the whole point of this being a
 * shared function, not two independently-drifting copies, per this
 * phase's own explicit instruction, §4).
 *
 * **Faz D.3 refactor, not a behavior change**: steps 3-8 (the canonical
 * chain validation) now delegate to `takeawayScope.ts`'s
 * `resolveActiveTakeawayBranch` — the exact same logic
 * `submitTakeawayOrder`'s authenticated-customer branch also calls, so
 * the two entry paths can never silently drift apart on what counts as a
 * "usable" branch. This function's own emulator test suite
 * (`takeawayGuestSession.test.ts`), unmodified, re-verifies the observable
 * behavior is unchanged.
 */
export async function resolveTakeawayQrTokenInternal(
  token: string,
): Promise<TakeawayQrResolution> {
  const db = getFirestore();

  const qrSnapshot = await db
    .collection("takeawayQrCodes")
    .where("opaqueToken", "==", token)
    .limit(1)
    .get();
  if (qrSnapshot.empty) {
    return { validityStatus: "notFound" };
  }
  const qrDoc = qrSnapshot.docs[0];
  const qr = qrDoc.data();

  const now = new Date();
  const qrExpiresAt = toDate(qr.expiresAt);
  const isQrPastExpiry = qrExpiresAt !== null && now >= qrExpiresAt;
  if (qr.status !== TAKEAWAY_QR_CODE_STATUS.active || isQrPastExpiry) {
    return { validityStatus: isQrPastExpiry ? "expired" : "invalid" };
  }

  const organizationId = qr.organizationId;
  const restaurantId = qr.restaurantId;
  const branchId = qr.branchId;
  if (
    typeof organizationId !== "string" ||
    typeof restaurantId !== "string" ||
    typeof branchId !== "string"
  ) {
    return { validityStatus: "notFound" };
  }

  const scope = await resolveActiveTakeawayBranch(db, {
    restaurantId,
    branchId,
    expectedOrganizationId: organizationId,
  });
  if (scope.status !== "valid") {
    return { validityStatus: scope.status };
  }

  return {
    validityStatus: "valid",
    organizationId,
    restaurantId,
    branchId,
    branchDisplayName: scope.branchDisplayName,
    qrCodeId: qrDoc.id,
  };
}
