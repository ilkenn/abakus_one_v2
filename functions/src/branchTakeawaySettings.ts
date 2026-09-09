import type { Firestore, Transaction } from "firebase-admin/firestore";
import { Timestamp } from "firebase-admin/firestore";

/**
 * AP-6 Sprint 1 — a branch's live, staff-controlled takeaway operational
 * mode: `branchTakeawaySettings/{branchId}`. Mirrors the Dart domain type
 * (`lib/features/takeaway/domain/models/branch_takeaway_settings.dart`) —
 * that file's own doc comment explains the deliberate separation from
 * `branchOperatingHours`/`ChannelOperationPolicy`.
 *
 * **Missing document = `active`** (the opposite fail-safe direction from
 * `branchOperatingHours`'s "missing = closed every day"): this collection
 * is an OVERRIDE on top of the pre-AP-6 default behavior, not the sole
 * gate on whether takeaway is available at all — a branch that has never
 * touched its takeaway mode must behave exactly as it did before this
 * sprint, not suddenly stop accepting orders.
 */

export type TakeawayOperationStatus = "active" | "busy" | "paused";

export const BRANCH_TAKEAWAY_BUSY_DELAY_OPTIONS: readonly number[] = [0, 15, 30, 45, 60];

export interface BranchTakeawaySettings {
  branchId: string;
  organizationId: string;
  restaurantId: string;
  status: TakeawayOperationStatus;
  busyDelayMinutes: number;
  pausedUntil: Date | null;
  updatedByStaffId: string;
  updatedAt: Date;
  revision: number;
}

function parseSettings(branchId: string, data: FirebaseFirestore.DocumentData): BranchTakeawaySettings {
  const status: TakeawayOperationStatus =
    data.status === "busy" || data.status === "paused" ? data.status : "active";
  const pausedUntilRaw = data.pausedUntil;
  return {
    branchId,
    organizationId: String(data.organizationId ?? ""),
    restaurantId: String(data.restaurantId ?? ""),
    status,
    busyDelayMinutes: Number.isFinite(data.busyDelayMinutes) ? Number(data.busyDelayMinutes) : 0,
    pausedUntil:
      typeof pausedUntilRaw?.toDate === "function" ? (pausedUntilRaw.toDate() as Date) : null,
    updatedByStaffId: String(data.updatedByStaffId ?? ""),
    updatedAt:
      typeof data.updatedAt?.toDate === "function" ? (data.updatedAt.toDate() as Date) : new Date(0),
    revision: Number.isFinite(data.revision) ? Number(data.revision) : 1,
  };
}

/**
 * Loads `branchTakeawaySettings/{branchId}` — `tx.get()` when [tx] is
 * supplied (this is an authoritative input to `submitTakeawayOrder`'s own
 * accept-immediately-vs-defer decision, so it must participate in that
 * transaction's read set), a plain read otherwise. `null` for a branch
 * with no document — the caller treats this as `active`, never a thrown
 * error (see this module's own doc comment for why that default direction
 * is the opposite of `branchOperatingHours`'s).
 */
export async function loadBranchTakeawaySettings(
  db: Firestore,
  branchId: string,
  tx?: Transaction,
): Promise<BranchTakeawaySettings | null> {
  const ref = db.collection("branchTakeawaySettings").doc(branchId);
  const doc = tx ? await tx.get(ref) : await ref.get();
  if (!doc.exists) return null;
  return parseSettings(branchId, doc.data()!);
}

/**
 * Whether a takeaway order submitted right now should be deferred to
 * `OrderStatus.scheduled` — true only while genuinely `paused` with a
 * still-future `pausedUntil` (a stale, already-past `pausedUntil` that the
 * sweep hasn't reverted yet is treated as already-active — mirrors the
 * Dart `BranchTakeawaySettings.isPausedAt` exactly).
 */
export function isPausedAt(settings: BranchTakeawaySettings | null, now: Date): boolean {
  if (!settings || settings.status !== "paused") return false;
  return settings.pausedUntil === null || now.getTime() < settings.pausedUntil.getTime();
}

/**
 * The extra delay (minutes) to add on top of the standard prep/delivery
 * estimate for an order submitted right now — `busyDelayMinutes` only
 * while genuinely `busy`, `0` otherwise (including `active`/`paused`/no
 * document at all).
 */
export function busyDelayMinutesAt(settings: BranchTakeawaySettings | null): number {
  if (!settings || settings.status !== "busy") return 0;
  return settings.busyDelayMinutes;
}

/** Firestore Timestamp helper, kept local so callers never hand-roll the conversion. */
export function toTimestamp(date: Date): Timestamp {
  return Timestamp.fromDate(date);
}
