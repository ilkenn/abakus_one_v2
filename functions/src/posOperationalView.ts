import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { TABLE_SESSIONS_COLLECTION, GUEST_SUB_ACCOUNTS_COLLECTION } from "./tableSessionConfig";
import { CHECKS_COLLECTION, CHECK_ALLOCATIONS_COLLECTION } from "./checkAllocationConfig";

/**
 * AP-3 Wave 1 SECURITY CORRECTION — the sole staff/POS read path for
 * `tableSessions`/`guestSubAccounts`/`checks`/`checkAllocations` (all four
 * have `allow read: if false` for every staff actor in `firestore.rules` —
 * see that file's own note on this correction). Firestore Rules cannot
 * verify AP-2's trusted-device challenge-response proof, so any rule
 * granting staff read on `isOrgMember`/`hasBranchAccess` claims alone would
 * be a real device-requirement bypass for POS-operational data. This
 * callable requires BOTH `requireStaffPermission` AND
 * `requireActiveDeviceSession` before reading anything, then returns one
 * minimized, purpose-built projection — never the raw documents verbatim
 * beyond what a cashier's table-detail screen actually needs.
 *
 * Read-only. No `.snapshots()` equivalent exists here by design (Admin SDK
 * callables can't push) — the intended Flutter client polls this on a
 * bounded interval / pull-to-refresh, trading real-time push for a genuine
 * server-verified device-binding guarantee on this specific, high-stakes
 * surface (corrected AP-3 Stage A report §10.3's own documented trade-off).
 *
 * Reuses `manageDineInOrders` (already staff-tier) rather than inventing a
 * new read-only permission — viewing a table's operational state is a
 * strict prerequisite of every mutation that permission already gates, and
 * this codebase's own established tiering deliberately avoids permission
 * proliferation (see `staffAuthorization.ts`'s own doc comment on
 * `manageDineInOrders`'s "minimum necessary lifecycle primitive" scope).
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}

export const getPosTableOperationalView = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const branchId = requireNonEmptyString(data.branchId, "branchId");
    const tableId = requireNonEmptyString(data.tableId, "tableId");
    const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
    const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");

    requireStaffPermission(request, organizationId, "manageDineInOrders");
    requireBranchAccess(request, organizationId, branchId);
    await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

    const db = getFirestore();
    const tableSnap = await db.collection("restaurantTables").doc(tableId).get();
    if (!tableSnap.exists || String(tableSnap.data()!.organizationId) !== organizationId || String(tableSnap.data()!.branchId) !== branchId) {
      throw new HttpsError("not-found", "Table not found.");
    }
    const table = tableSnap.data()!;
    const activeTableSessionId = (table.activeTableSessionId as string | null | undefined) ?? null;

    if (!activeTableSessionId) {
      return {
        tableId,
        status: (table.statusOverride as string | undefined) ?? String(table.status ?? "available"),
        tableSession: null,
        subAccounts: [],
        checks: [],
        allocations: [],
        orders: [],
      };
    }

    const tableSessionSnap = await db.collection(TABLE_SESSIONS_COLLECTION).doc(activeTableSessionId).get();
    if (!tableSessionSnap.exists) {
      throw new HttpsError("failed-precondition", "Table points at a table session that no longer exists.");
    }
    const tableSession = tableSessionSnap.data()!;

    const [subAccountsSnap, checksSnap, ordersSnap] = await Promise.all([
      db.collection(GUEST_SUB_ACCOUNTS_COLLECTION).where("tableSessionId", "==", activeTableSessionId).get(),
      db.collection(CHECKS_COLLECTION).where("tableSessionId", "==", activeTableSessionId).get(),
      db.collection("orders").where("dineInSessionGroupId", "==", activeTableSessionId).get(),
    ]);

    const checkIds = checksSnap.docs.map((d) => d.id);
    const allocations: FirebaseFirestore.QueryDocumentSnapshot[] = [];
    // Firestore `in` queries are capped at 30 values — chunk defensively;
    // a real table realistically has a small, bounded number of checks.
    for (let i = 0; i < checkIds.length; i += 30) {
      const chunk = checkIds.slice(i, i + 30);
      if (chunk.length === 0) continue;
      const snap = await db.collection(CHECK_ALLOCATIONS_COLLECTION).where("checkId", "in", chunk).get();
      allocations.push(...snap.docs);
    }

    return {
      tableId,
      status: (table.statusOverride as string | undefined) ?? String(table.status ?? "occupied"),
      tableSession: { id: tableSessionSnap.id, ...tableSession },
      subAccounts: subAccountsSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
      checks: checksSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
      allocations: allocations.map((d) => ({ id: d.id, ...d.data() })),
      orders: ordersSnap.docs.map((d) => {
        const o = d.data();
        return {
          id: d.id,
          subAccountId: o.subAccountId,
          mode: o.mode,
          linesDispositionSummary: o.linesDispositionSummary,
          lines: (o.lines ?? []).map((line: Record<string, unknown>) => ({
            productName: line.productName,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            status: line.status,
            subAccountId: line.subAccountId,
          })),
        };
      }),
    };
  },
);
