import type { Transaction, Firestore, Timestamp } from "firebase-admin/firestore";
import { Timestamp as FirestoreTimestamp } from "firebase-admin/firestore";

/**
 * `printJobEngine.ts` — AP-5 Sprint 4.
 *
 * Builds out Sprint 1's bare `PrintJob`/`PrinterConfig` domain skeleton
 * (`lib/features/printing/domain/print_job.dart` — "models the print-job
 * /queue shape only, mirroring `KitchenPrintAttempt`'s existing real shape,
 * not a working printer") into a real, durable `printJobs` queue —
 * deliberately the NEWER queue-shaped system, left as a distinct track
 * from the older `KitchenPrintAttempt`/`PrintKitchenTicketWithRetry`
 * attempt-log (`kitchen_ticket_print_provider.dart`), which this sprint
 * does not touch.
 *
 * `derivePrintJobId` mirrors `PrintJob.derivePrintJobId` (Dart) exactly —
 * same `print-${orderId}-${stationId}-gen${attemptGeneration}` shape, kept
 * identical between the two languages the same way `KitchenLineStatus`'s
 * transition table already is.
 *
 * No real printer hardware/worker exists yet (`docs/kds_printer_stock_
 * architecture.md` §24's own gate, same class of external dependency as
 * AP-4's PAX/GMP-3 fiscal boundary) — `resolveMockPrintOutcome` is the
 * safe adapter/mock interface that stands in for a real `PrinterAdapter`:
 * deterministic, not random, and swappable for a real transport later
 * without changing any caller's shape.
 */

export function derivePrintJobId(
  orderId: string,
  stationId: string,
  attemptGeneration: number,
): string {
  return `print-${orderId}-${stationId}-gen${attemptGeneration}`;
}

export interface PreparePrintJobForAcceptanceParams {
  tx: Transaction;
  db: Firestore;
  organizationId: string;
  branchId: string;
  orderId: string;
  stationId: string;
  now: Timestamp;
}

interface PrintJobPlan {
  printJobId: string;
  data: Record<string, unknown>;
}

/**
 * Read phase only — must be called before the enclosing transaction's own
 * first write (same discipline `prepareKitchenWorkAndStockConsumption`
 * already established). Returns `null` when a print job for this
 * (order, station, generation 0) already exists — the deterministic id
 * makes a duplicate/retried acceptance call a pure no-op, never a second
 * job, satisfying "prevent duplicate receipt printing at server/data
 * level via unique printJobId + idempotency key."
 */
export async function preparePrintJobForAcceptance(
  params: PreparePrintJobForAcceptanceParams,
): Promise<PrintJobPlan | null> {
  const { tx, db, organizationId, branchId, orderId, stationId, now } = params;
  const printJobId = derivePrintJobId(orderId, stationId, 0);
  const ref = db.collection("printJobs").doc(printJobId);
  const snap = await tx.get(ref);
  if (snap.exists) return null;
  return {
    printJobId,
    data: {
      organizationId,
      branchId,
      orderId,
      stationId,
      status: "pending",
      retryCount: 0,
      backupPrinterId: null,
      isCopy: false,
      requestedByUid: null,
      requestedAt: now,
      updatedAt: now,
    },
  };
}

/** Write phase only — no reads. Safe to call anywhere after `prepare...`
 * within the same transaction. */
export function applyPrintJobPlan(
  tx: Transaction,
  db: Firestore,
  plan: PrintJobPlan | null,
): void {
  if (!plan) return;
  tx.set(db.collection("printJobs").doc(plan.printJobId), plan.data);
}

/**
 * The mock transport: deterministic, not random. A branch/station pair
 * with at least one registered `printerConfigs` document "prints"
 * successfully; one with none fails — mirrors
 * `NoOpKitchenTicketPrintProvider`'s own "no configured provider ->
 * unavailable" precedent, just at the queue layer instead of the
 * attempt-log layer. Deliberately a single-field `branchId` query +
 * in-memory `stationId` filter (never a compound `.where().where()`) so no
 * new Firestore composite index is required — a branch has few printers,
 * so this is a small in-memory list, not a scalability concern.
 */
export async function resolveMockPrintOutcome(
  db: Firestore,
  branchId: string,
  stationId: string,
): Promise<"success" | "failed"> {
  const snap = await db.collection("printerConfigs").where("branchId", "==", branchId).get();
  const hasConfiguredPrinter = snap.docs.some((doc) => doc.data().stationId === stationId);
  return hasConfiguredPrinter ? "success" : "failed";
}

/**
 * Drives an already-created `pending` print job through the mock
 * transport, in two separate (non-transactional) writes — genuinely
 * observable `pending -> printing -> success/failed`, not one atomic
 * commit that would hide the intermediate state from a reader/test.
 * Never called for a job whose status is already terminal (see
 * `requestPrintJob.ts`'s idempotent-replay branch, which returns the
 * existing terminal status directly instead of re-driving it).
 */
export async function processPrintJob(
  db: Firestore,
  printJobId: string,
  branchId: string,
  stationId: string,
): Promise<"success" | "failed"> {
  const ref = db.collection("printJobs").doc(printJobId);
  await ref.update({ status: "printing", updatedAt: FirestoreTimestamp.now() });
  const outcome = await resolveMockPrintOutcome(db, branchId, stationId);
  await ref.update({ status: outcome, updatedAt: FirestoreTimestamp.now() });
  return outcome;
}
