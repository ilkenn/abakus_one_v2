import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import type { DocumentSnapshot } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { loadReservationPolicy } from "./reservationConfig";
import { isMinuteAligned } from "./reservationAvailability";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import {
  checkTableOccupancyConflict,
  lockTableOccupancyBuckets,
  releaseTableOccupancyBuckets,
  computeReservationTableBuckets,
  reservationTableBucketId,
} from "./reservationTableOccupancy";
import {
  computeProtectionWindow,
  computeProtectionMinutes,
  lockTableProtectionMinuteBuckets,
  removeReservationTableProtection,
  tableProtectionMinuteBucketId,
} from "./reservationTableProtection";
import { activeReservationTableContextRef, readLiveReservationTableContext } from "./reservationTableContext";

/**
 * Physical table assignment (+ atomic reassignment) — Faz R.1C.1
 * (`docs/decisions.md` ADR-027 Faz R.1C.1 design). Server-authoritative
 * staff action mirroring `respondToReservation.ts`'s own shape: a single
 * `db.runTransaction`, `manageReservations` permission (via
 * `staffAuthorization.ts`, Faz R.1B.1's generic resolver — never a
 * role-name check embedded here), `tx.get()` for every authoritative read,
 * every bucket read batched before any bucket write (the exact ordering
 * fix Faz R.1B's own `reservationHoldOps.ts` needed).
 *
 * **Scope, explicitly**: physical table assignment/reassignment + the
 * occupancy/protection *data* this creates. No QR enforcement, no
 * preorder/KDS, no UI — all later phases' work, per Faz R.1C.1's own
 * explicit instruction.
 *
 * **Faz R.1C.2 update**: reassignment now hard-fails while this exact
 * Reservation's `activeReservationTableContext` on its *current* table is
 * live (`readLiveReservationTableContext`, `reservationTableContext.ts`) —
 * no silent context migration. Staff must `closeReservationTable` first.
 *
 * **`restaurantTables` <-> `reservationAreas` linkage — a genuine data-
 * model addition, disclosed, not silent.** Research before implementing
 * (this phase's own "önce mevcut pattern'leri analiz et" instruction)
 * confirmed no canonical relation between `restaurantTables` and
 * `reservationAreas` exists anywhere in this codebase —
 * `restaurantTables.areaName` is free text (`docs/table_qr_architecture
 * .md`'s own deliberate exception to "no free-form strings"), never a
 * foreign key. This function requires a new, additive, nullable
 * `restaurantTables.reservationAreaId` field (matched against the
 * Reservation's own `confirmedAreaId`) — no existing reader is affected
 * (there is no callable write path to `restaurantTables` today; only the
 * dev seed script writes it, updated alongside this phase). A table with
 * no `reservationAreaId` set fails closed, `failed-precondition` — never
 * silently allowed into an area it was never actually declared to belong
 * to. The Dart `RestaurantTable` domain model is deliberately NOT updated
 * this phase — no UI consumes this field yet.
 *
 * **Firestore write-limit safety (Faz R.1C.1 §12).** A transaction is
 * subject to the same ~500-mutation cap as a batched write. Worst case
 * (reassignment) writes `2 x occupancyBucketCount + 2 x minuteBucketCount +
 * 3` documents — dominated by `minuteBucketCount = PROTECTION_LEAD_MINUTES
 * + reservationDurationMinutes` (one document per minute), not bounded by
 * any existing policy validation. `MAX_RESERVATION_DURATION_MINUTES_FOR_
 * TABLE_ASSIGNMENT` is a new, backend-only structural cap (mirrors
 * `submitReservation.ts`'s own `MAX_PARTY_SIZE_HARD_CAP` precedent — a
 * bound independent of any single policy's own configured values) *and*
 * this function still computes the real worst-case write count and fails
 * closed, `resource-exhausted`, before attempting a single write, if it
 * would exceed a safe threshold — belt-and-suspenders, since a pathological
 * `slotIntervalMinutes` could otherwise blow the budget even under the
 * duration cap alone.
 */

const MAX_RESERVATION_DURATION_MINUTES_FOR_TABLE_ASSIGNMENT = 180;
/** Firestore's real per-transaction mutation cap is ~500; this margin leaves headroom for the reservation/table/protection-doc writes counted separately below. */
const SAFE_MAX_TRANSACTION_WRITES = 450;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

export const assignReservationTable = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.reservationId !== "string" || data.reservationId.length === 0) {
      invalid("reservationId is required.");
    }
    if (typeof data.tableId !== "string" || data.tableId.length === 0) {
      invalid("tableId is required.");
    }
    const reservationId = data.reservationId as string;
    const tableId = data.tableId as string;

    const db = getFirestore();
    const reservationRef = db.collection("reservations").doc(reservationId);
    const tableRef = db.collection("restaurantTables").doc(tableId);

    return db.runTransaction(async (tx) => {
      // ---------------------------------------------------------------
      // Reads, part 1 — authoritative Reservation, RestaurantTable,
      // ReservationPolicy. Client-supplied organizationId/restaurantId/
      // branchId are never authorization/scope truth — every scope check
      // below compares against the Reservation's own already-verified,
      // server-written fields.
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
          `A physical table can only be assigned to a confirmed reservation (current status: ${reservation.status}).`,
        );
      }
      if (!reservation.confirmedTime || !reservation.confirmedAreaId) {
        // Defensive — a confirmed Reservation always has both fields set
        // (respondToReservation.ts/respondToProposedChange.ts's own
        // invariant), but never trusted blindly.
        throw new HttpsError(
          "failed-precondition",
          "Reservation is confirmed but missing confirmedTime/confirmedAreaId.",
        );
      }

      const confirmedTime = toDate(reservation.confirmedTime);
      // Faz R.0.7 §2 invariant — fail closed, never silently rounded.
      if (!isMinuteAligned(confirmedTime)) {
        throw new HttpsError("internal", "Stored confirmedTime is not minute-aligned.");
      }

      const tableDoc = await tx.get(tableRef);
      if (!tableDoc.exists) {
        throw new HttpsError("not-found", "Table not found.");
      }
      const table = tableDoc.data()!;
      // Cross-tenant fails closed as not-found, not a distinguishable
      // "invalid" — mirrors resolveReservationArea's own not-found-not-an-
      // existence-oracle precedent (Faz R.0.6 §9).
      if (
        table.organizationId !== reservation.organizationId ||
        table.restaurantId !== reservation.restaurantId ||
        table.branchId !== reservation.branchId
      ) {
        throw new HttpsError("not-found", "Table not found.");
      }
      if (table.isActive !== true) {
        throw new HttpsError("failed-precondition", "This table is not currently active.");
      }
      if (table.reservationAreaId !== reservation.confirmedAreaId) {
        throw new HttpsError(
          "failed-precondition",
          "This table does not belong to the reservation's confirmed area.",
        );
      }

      const policy = await loadReservationPolicy(tx, db, reservation.branchId);
      if (!policy) {
        throw new HttpsError("failed-precondition", "This branch has no reservation policy configured.");
      }
      if (policy.reservationDurationMinutes > MAX_RESERVATION_DURATION_MINUTES_FOR_TABLE_ASSIGNMENT) {
        throw new HttpsError(
          "failed-precondition",
          `reservationDurationMinutes (${policy.reservationDurationMinutes}) exceeds the maximum ` +
            `supported for physical table assignment (${MAX_RESERVATION_DURATION_MINUTES_FOR_TABLE_ASSIGNMENT}).`,
        );
      }

      const existingAssignedTableId = (reservation.assignedTableId as string | null) ?? null;

      // Idempotency — an exact retry of the same assignment (first-time or
      // reassignment-to-the-same-table) is a safe no-op, no re-mutation.
      if (existingAssignedTableId === tableId) {
        return { reservationId, tableId, assigned: true, duplicate: true };
      }

      const now = new Date();

      // Faz R.1C.2 §18 — reassigning a table out from under a *live*
      // reservation table context is never allowed; silent context
      // migration is explicitly forbidden. Staff workflow is
      // closeReservationTable -> assignReservationTable -> openReservation
      // Table, never a reassign-while-open shortcut.
      if (existingAssignedTableId) {
        const oldContextRef = activeReservationTableContextRef(db, existingAssignedTableId);
        const liveOldContext = await readLiveReservationTableContext(oldContextRef, now, tx);
        if (liveOldContext && liveOldContext.reservationId === reservationId) {
          throw new HttpsError(
            "failed-precondition",
            "This reservation's table context is currently open — close it (closeReservationTable) before reassigning.",
          );
        }
      }

      const occupancyStart = confirmedTime;
      const occupancyEnd = new Date(
        confirmedTime.getTime() + policy.reservationDurationMinutes * 60_000,
      );
      const { protectionStartAt, protectionEndAt } = computeProtectionWindow(
        confirmedTime,
        policy.reservationDurationMinutes,
      );
      const protectionMinutes = computeProtectionMinutes(protectionStartAt, protectionEndAt);

      const newOccupancyBuckets = computeReservationTableBuckets(
        tableId,
        occupancyStart,
        occupancyEnd,
        policy.slotIntervalMinutes,
      );

      // Faz R.1C.1 §12 — computed before any read/write of the buckets
      // themselves; a pathological policy (tiny slotIntervalMinutes, long
      // duration) must fail closed with a clear error, never attempt a
      // transaction Firestore itself would reject.
      const estimatedWrites =
        2 * newOccupancyBuckets.length + 2 * protectionMinutes.length + 3;
      if (estimatedWrites > SAFE_MAX_TRANSACTION_WRITES) {
        throw new HttpsError(
          "resource-exhausted",
          `This branch's reservation policy (slotIntervalMinutes=${policy.slotIntervalMinutes}, ` +
            `reservationDurationMinutes=${policy.reservationDurationMinutes}) would require ` +
            `${estimatedWrites} writes to assign a physical table, exceeding the safe transaction ` +
            `limit (${SAFE_MAX_TRANSACTION_WRITES}).`,
        );
      }

      // ---------------------------------------------------------------
      // Reads, part 2 — new table's occupancy buckets (conflict check),
      // and, only when reassigning, the old table's occupancy buckets +
      // the old table's protection-minute buckets. All reads still happen
      // before any write.
      // ---------------------------------------------------------------
      const { conflict, buckets: readNewOccupancyBuckets } = await checkTableOccupancyConflict(db, tx, {
        tableId,
        start: occupancyStart,
        end: occupancyEnd,
        slotIntervalMinutes: policy.slotIntervalMinutes,
        reservationId,
      });
      if (conflict) {
        throw new HttpsError(
          "failed-precondition",
          "This table is already booked for an overlapping time.",
        );
      }

      let oldOccupancyDocs: DocumentSnapshot[] = [];
      let oldOccupancyBuckets: { id: string; slotStart: Date }[] = [];
      let oldMinuteDocs: DocumentSnapshot[] = [];
      if (existingAssignedTableId) {
        oldOccupancyBuckets = computeReservationTableBuckets(
          existingAssignedTableId,
          occupancyStart,
          occupancyEnd,
          policy.slotIntervalMinutes,
        );
        oldOccupancyDocs = await Promise.all(
          oldOccupancyBuckets.map((b) =>
            tx.get(db.collection("reservationTableOccupancy").doc(b.id)),
          ),
        );
        oldMinuteDocs = await Promise.all(
          protectionMinutes.map((m) =>
            tx.get(
              db
                .collection("tableProtectionMinuteBuckets")
                .doc(tableProtectionMinuteBucketId(existingAssignedTableId, m)),
            ),
          ),
        );
      }

      // ---------------------------------------------------------------
      // Writes — every read above is done; nothing below issues another
      // tx.get().
      // ---------------------------------------------------------------
      if (existingAssignedTableId) {
        releaseTableOccupancyBuckets(tx, db, {
          buckets: oldOccupancyBuckets,
          existingDocs: oldOccupancyDocs,
          reservationId,
        });
        removeReservationTableProtection(tx, db, {
          tableId: existingAssignedTableId,
          reservationId,
          minutes: protectionMinutes,
          existingDocs: oldMinuteDocs,
        });
      }

      lockTableOccupancyBuckets(tx, db, {
        buckets: readNewOccupancyBuckets,
        tableId,
        reservationId,
        organizationId: reservation.organizationId,
        restaurantId: reservation.restaurantId,
        branchId: reservation.branchId,
      });
      lockTableProtectionMinuteBuckets(tx, db, {
        tableId,
        reservationId,
        minutes: protectionMinutes,
        organizationId: reservation.organizationId,
        restaurantId: reservation.restaurantId,
        branchId: reservation.branchId,
      });

      const protectionPayload: Record<string, unknown> = {
        reservationId,
        organizationId: reservation.organizationId,
        restaurantId: reservation.restaurantId,
        branchId: reservation.branchId,
        tableId,
        protectionStartAt,
        protectionEndAt,
        bucketIds: newOccupancyBuckets.map((b) => reservationTableBucketId(tableId, b.slotStart)),
        active: true,
        updatedAt: now,
      };
      if (!existingAssignedTableId) {
        protectionPayload.createdAt = now;
      }
      tx.set(db.collection("reservationTableProtections").doc(reservationId), protectionPayload, {
        merge: true,
      });

      tx.set(
        reservationRef,
        {
          assignedTableId: tableId,
          updatedAt: now,
        },
        { merge: true },
      );

      return {
        reservationId,
        tableId,
        assigned: true,
        duplicate: false,
        reassigned: existingAssignedTableId !== null,
      };
    });
  },
);
