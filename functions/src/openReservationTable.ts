import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { activeReservationTableContextRef, readLiveReservationTableContext } from "./reservationTableContext";
import {
  computeProtectionMinutes,
  removeReservationTableProtection,
  tableProtectionMinuteBucketId,
} from "./reservationTableProtection";

/**
 * Opens a confirmed Reservation's assigned physical table for real dine-in
 * use — Faz R.1C.2 §5-§9. Server-authoritative staff action:
 * `manageReservations` permission (via `staffAuthorization.ts`, never a
 * role check embedded here), `tableId` always resolved server-side from
 * `Reservation.assignedTableId` — never a client-supplied table id.
 *
 * **Two-step conflict handshake (§6-§7)**: an active *walk-in* table guest
 * session on the same table is a soft conflict — the first call (`acknowl
 * edgeActiveSessionConflict` omitted/`false`) mutates nothing and returns a
 * structured `activeSessionExists` conflict; staff can retry with `true`
 * to proceed anyway. An active context belonging to a *different*
 * Reservation is a hard conflict — `acknowledgeActiveSessionConflict` can
 * never override it, because two Reservations can never simultaneously own
 * one physical table's context. Every call — including the acknowledged
 * retry — re-reads and re-validates the full canonical state from
 * scratch inside one transaction; there is no cross-call caching for a
 * second call to trust stale results from.
 */

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export const openReservationTable = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const staffUid = request.auth.uid;

    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.reservationId !== "string" || data.reservationId.length === 0) {
      invalid("reservationId is required.");
    }
    const reservationId = data.reservationId as string;
    // Only an explicit `true` opts in — any other value (missing, falsy,
    // malformed) is treated as "not acknowledged," fail-safe.
    const acknowledge = data.acknowledgeActiveSessionConflict === true;

    const db = getFirestore();
    const reservationRef = db.collection("reservations").doc(reservationId);

    return db.runTransaction(async (tx) => {
      // ---------------------------------------------------------------
      // Reads
      // ---------------------------------------------------------------
      const reservationDoc = await tx.get(reservationRef);
      if (!reservationDoc.exists) {
        throw new HttpsError("not-found", "Reservation not found.");
      }
      const reservation = reservationDoc.data()!;

      requireStaffPermission(request, reservation.organizationId, "manageReservations");

      if (reservation.status !== "confirmed") {
        throw new HttpsError(
          "failed-precondition",
          `Reservation is not confirmed (current status: ${reservation.status}).`,
        );
      }
      const tableId = reservation.assignedTableId as string | null;
      if (!tableId) {
        throw new HttpsError("failed-precondition", "Reservation has no assigned table.");
      }
      if (!reservation.confirmedTime) {
        throw new HttpsError("failed-precondition", "Reservation is confirmed but missing confirmedTime.");
      }

      const protectionRef = db.collection("reservationTableProtections").doc(reservationId);
      const protectionDoc = await tx.get(protectionRef);
      if (!protectionDoc.exists) {
        throw new HttpsError(
          "failed-precondition",
          "No table protection record found for this reservation's assigned table.",
        );
      }
      const protection = protectionDoc.data()!;
      if (protection.tableId !== tableId) {
        // Defensive — assignReservationTable always keeps these in sync;
        // fail closed rather than open the wrong table's context.
        throw new HttpsError(
          "failed-precondition",
          "The reservation's protection record does not match its assigned table.",
        );
      }

      const now = new Date();
      const contextEndAt = toDate(protection.protectionEndAt);
      if (contextEndAt.getTime() <= now.getTime()) {
        throw new HttpsError(
          "failed-precondition",
          "This reservation's table-context window has already ended.",
        );
      }

      const contextRef = activeReservationTableContextRef(db, tableId);
      const liveContext = await readLiveReservationTableContext(contextRef, now, tx);
      if (liveContext) {
        if (liveContext.reservationId === reservationId) {
          // Idempotent retry — already opened, nothing to redo.
          return { reservationId, tableId, opened: true, duplicate: true };
        }
        // Faz R.1C.2 §7 — never overridable by acknowledgeActiveSessionConflict.
        throw new HttpsError(
          "failed-precondition",
          "Another reservation's table context is already active for this table.",
        );
      }

      // Faz R.1C.2 §6 — active walk-in session conflict check. Not the QR
      // hot path (§1's "no query" rule is scoped to that path only) — a
      // staff-initiated, low-frequency action, where a query is the only
      // way to enumerate "which sessions are open on this table."
      const activeSessionsSnapshot = await tx.get(
        db
          .collection("tableGuestSessions")
          .where("tableId", "==", tableId)
          .where("status", "==", "active"),
      );
      const conflictingSessionCount = activeSessionsSnapshot.docs.filter((doc) => {
        const session = doc.data();
        const isLive = toDate(session.expiresAt).getTime() > now.getTime();
        const belongsToThisReservation = session.reservationContextId === reservationId;
        return isLive && !belongsToThisReservation;
      }).length;

      if (conflictingSessionCount > 0 && !acknowledge) {
        throw new HttpsError(
          "failed-precondition",
          "An active walk-in table session already exists for this table.",
          { code: "activeSessionExists", conflictingSessionCount },
        );
      }

      const protectionStartAt = toDate(protection.protectionStartAt);
      const minutes = computeProtectionMinutes(protectionStartAt, contextEndAt);
      const minuteRefs = minutes.map((m) =>
        db.collection("tableProtectionMinuteBuckets").doc(tableProtectionMinuteBucketId(tableId, m)),
      );
      const minuteDocs = await Promise.all(minuteRefs.map((ref) => tx.get(ref)));

      // ---------------------------------------------------------------
      // Writes — every read above is done.
      // ---------------------------------------------------------------
      removeReservationTableProtection(tx, db, {
        tableId,
        reservationId,
        minutes,
        existingDocs: minuteDocs,
      });
      tx.set(protectionRef, { active: false, updatedAt: now }, { merge: true });
      tx.set(contextRef, {
        reservationId,
        organizationId: reservation.organizationId,
        restaurantId: reservation.restaurantId,
        branchId: reservation.branchId,
        tableId,
        openedByStaffId: staffUid,
        openedAt: now,
        contextEndAt,
        active: true,
        closedAt: null,
        closedByStaffId: null,
        updatedAt: now,
      });

      return { reservationId, tableId, opened: true, duplicate: false };
    });
  },
);
