import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore } from "firebase-admin/firestore";
import type { Firestore, DocumentReference, DocumentData } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

/**
 * Faz R.3C/R.3C.1 — consumes the existing `reservationEvents` transactional
 * outbox (Faz R.1B §17/R.1B.1/R.3B §17, unchanged) to deliver a real
 * customer push notification. Deliberately an asynchronous CONSUMER, never
 * folded into the state-transition transaction that produces an event —
 * every reservation callable (`submitReservation`/`respondToReservation`/
 * `respondToProposedChange`/`reservationSweep`/`cancelReservation`) is
 * completely untouched by this phase.
 *
 * **Which events generate a notification — product classification, not an
 * invented rule.** Six of the ten existing event types are customer-
 * relevant enough to interrupt them: `reservationConfirmed`,
 * `reservationRejected`, `reservationChangeProposed`,
 * `reservationChangeExpired`, `reservationResponseTimedOut`,
 * `reservationCancelled`. Deliberately excluded, each for a stated reason:
 * `reservationChangeAccepted`/`reservationChangeRejected` are always the
 * *customer's own* just-completed action (`respondToProposedChange`) — a
 * push telling someone what they themselves just did a second ago is
 * noise, not information. `reservationCompleted`/`reservationNoShow`
 * (challenged per this phase's own explicit instruction before including
 * them) are backward-looking, non-actionable records of something already
 * over — no confirmation dialog, no deadline, nothing for the customer to
 * do with the information at push-notification urgency; a customer who
 * cares can already see the completed/no-show status in-app. No new event
 * type was invented to work around this list.
 */

export type ReservationNotificationEventType =
  | "reservationConfirmed"
  | "reservationRejected"
  | "reservationChangeProposed"
  | "reservationChangeExpired"
  | "reservationResponseTimedOut"
  | "reservationCancelled";

export interface NotificationCopy {
  title: string;
  body: string;
}

/**
 * §12 — LOCKED-style minimal lock-screen copy: never a phone number,
 * party size, preorder contents, or reject reason. A sensitive detail (the
 * restaurant's actual reject/cancellation reason) belongs in the app's own
 * detail screen, never the push body. `reservationResponseTimedOut`
 * deliberately reuses the exact same copy as `reservationRejected` — the
 * underlying `Reservation.status` is `'rejected'` either way (only
 * `reasonCode` differs, Faz R.1B's own "no reason-specific status" design)
 * and the customer-facing outcome is identical: no reservation, must
 * rebook.
 */
export function buildReservationNotificationCopy(
  eventType: string,
): NotificationCopy | null {
  switch (eventType as ReservationNotificationEventType) {
    case "reservationConfirmed":
      return { title: "Abaküs", body: "Rezervasyonunuz onaylandı" };
    case "reservationRejected":
    case "reservationResponseTimedOut":
      return { title: "Abaküs", body: "Rezervasyon talebinizle ilgili bir güncelleme var" };
    case "reservationChangeProposed":
      return { title: "Abaküs", body: "Restoran rezervasyonunuz için yeni bir saat önerdi" };
    case "reservationChangeExpired":
      return { title: "Abaküs", body: "Rezervasyon önerisi için yanıt süresi doldu" };
    case "reservationCancelled":
      return { title: "Abaküs", body: "Rezervasyonunuz iptal edildi" };
    default:
      return null; // not a notifiable event type — see the module doc comment.
  }
}

export interface PushSendResult {
  successCount: number;
  /** Tokens FCM reports as permanently invalid (unregistered/uninstalled) — deactivated after send, never left to fail silently forever. */
  invalidTokens: string[];
}

export interface PushPayload extends NotificationCopy {
  data: Record<string, string>;
}

/**
 * §18 — the one seam that makes this module testable without a real FCM
 * emulator (none exists in the Firebase Local Emulator Suite). Production
 * wires [defaultSender], which detects the local emulator
 * (`FIRESTORE_EMULATOR_HOST`/`FUNCTIONS_EMULATOR` — the same real,
 * documented detection `appCheckConfig.ts`'s `shouldEnforceAppCheck`
 * already established) and substitutes a safe no-op that never calls
 * Google's real FCM API — every other part of the pipeline (idempotency,
 * recipient resolution, delivery-record bookkeeping) still runs for real
 * against the emulator. Tests call [processReservationEventForDelivery]/
 * [runReservationNotificationRetrySweep] directly with an explicit fake
 * [PushSender] for full control — never a real external FCM dependency.
 */
export type PushSender = (tokens: string[], payload: PushPayload) => Promise<PushSendResult>;

async function realFcmSender(tokens: string[], payload: PushPayload): Promise<PushSendResult> {
  if (tokens.length === 0) return { successCount: 0, invalidTokens: [] };
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: payload.title, body: payload.body },
    data: payload.data,
  });
  const invalidTokens: string[] = [];
  response.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error?.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token" ||
      code === "messaging/invalid-argument"
    ) {
      invalidTokens.push(tokens[i]);
    }
  });
  return { successCount: response.successCount, invalidTokens };
}

function isEmulatorContext(): boolean {
  return Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FUNCTIONS_EMULATOR);
}

const emulatorSafeNoopSender: PushSender = async (tokens) => {
  logger.info(
    `[reservationNotificationDelivery] emulator/local context — not calling real FCM ` +
      `(${tokens.length} token(s) would have been targeted).`,
  );
  return { successCount: tokens.length, invalidTokens: [] };
};

export function defaultSender(): PushSender {
  return isEmulatorContext() ? emulatorSafeNoopSender : realFcmSender;
}

export interface ProcessResult {
  processed: boolean;
  reason?: string;
}

// -----------------------------------------------------------------------
// Faz R.3C.1 — retry-safe delivery state machine.
//
// R.3C's original design claimed `reservationNotificationDeliveries/
// {eventId}` via `.create()` *before* calling `sender()`, then never
// revisited the record again. That made a **crash or transient failure
// between the claim and the send permanent, silent notification loss** —
// any later invocation (a retried trigger, a manual replay) immediately
// hit `ALREADY_EXISTS` on the claim and returned early, never attempting
// to send. This was flagged as a real production blocker and is what this
// revision fixes.
//
// **Chosen design — a lease/visibility-timeout state machine**, the same
// family of pattern this codebase's own `reservationPreorderKdsRelease`
// scheduler already established (bounded candidate query on a due
// timestamp field, one independent re-validating transaction per
// candidate, failure isolation) — reused rather than inventing a new
// convention:
//
//   status: 'pending' | 'delivered' | 'skipped' | 'permanentlyFailed'
//   attemptCount, claimedAt, deliveredAt, lastErrorCode
//   nextAttemptAt / nextAttemptAtTimestamp — dual ISO+Timestamp
//     representation (mirrors `kitchenReleaseAt`/`kitchenReleaseAtTimestamp`'s
//     own established precedent). While `status === 'pending'`, this is
//     "when this becomes eligible for an attempt" (now, for a fresh event;
//     now + backoff, after a failed send). A **claim pushes this value
//     forward** by [LEASE_DURATION_MS] without changing `status` — the
//     field doubles as a lease/visibility-timeout: a worker that crashes
//     mid-attempt leaves the record claimable again once the lease
//     expires, with no separate "processing" status needed to model that.
//
// `delivered`/`skipped`/`permanentlyFailed` are terminal — a claim is
// refused once any of them is reached, verified fresh, inside the claim
// transaction, never trusted from an earlier read (mirrors this
// codebase's "re-verify inside the transaction" convention throughout,
// e.g. `buildPreorderKdsReleasePatch`).
//
// **Honest limit, disclosed, not glossed over**: FCM itself does not
// offer a transactional "send" primitive — a worker can crash in the
// narrow window *after* `sender()` has already succeeded but *before*
// this module records that success. In that specific window a genuinely
// already-delivered push can be sent again by a later retry. This design
// eliminates the *lost-forever* failure mode R.3C actually shipped with;
// it does not, and cannot, claim mathematically perfect exactly-once
// delivery — no design built on top of FCM can. The guarantee this module
// provides is: a successful attempt is idempotent and terminal, a failed
// attempt is retried up to [MAX_ATTEMPTS] times, and two workers racing
// the same candidate normally resolve to exactly one winner (Firestore's
// own transaction contention retry, not additional locking).
// -----------------------------------------------------------------------

const LEASE_DURATION_MS = 5 * 60 * 1000; // 5 minutes — matches the sweep's own cadence below.
const RETRY_BACKOFF_MS = 5 * 60 * 1000; // fixed backoff — simplest correct choice for a low-volume, non-critical channel; revisit if real volume ever justifies exponential backoff.
const MAX_ATTEMPTS = 5;
const SWEEP_BATCH_SIZE = 50; // mirrors `PREORDER_KDS_RELEASE_BATCH_SIZE`'s own bound.

type DeliveryStatus = "pending" | "delivered" | "skipped" | "permanentlyFailed";

interface DeliveryDocSeed {
  eventId: string;
  type: string;
  reservationId: string;
}

function deliveryCollection(db: Firestore) {
  return db.collection("reservationNotificationDeliveries");
}

/**
 * Idempotently ensures a `pending`, immediately-due delivery record exists
 * for [seed]. A duplicate trigger invocation for the same `reservationEvents`
 * document (Firestore's "at least once" delivery) always hits
 * `ALREADY_EXISTS` here and is treated as expected, not an error — the
 * record it collided with is what [attemptDelivery] then claims/reuses.
 */
async function ensureDeliveryRecordExists(
  ref: DocumentReference<DocumentData>,
  seed: DeliveryDocSeed,
  now: Date,
): Promise<void> {
  try {
    await ref.create({
      eventId: seed.eventId,
      type: seed.type,
      reservationId: seed.reservationId,
      status: "pending" satisfies DeliveryStatus,
      attemptCount: 0,
      claimedAt: null,
      deliveredAt: null,
      lastErrorCode: null,
      nextAttemptAt: now.toISOString(),
      nextAttemptAtTimestamp: now,
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
    });
  } catch (error: unknown) {
    const code = (error as { code?: number | string })?.code;
    if (code === 6 || code === "already-exists") return;
    throw error;
  }
}

interface ClaimResult {
  claimed: boolean;
  attemptCount: number;
  /** Set only when NOT claimed — why, for the caller's own `reason`. */
  currentStatus?: DeliveryStatus;
}

/**
 * Atomically claims [ref] for one delivery attempt — refuses a terminal
 * status, refuses an unexpired lease held by a concurrent worker, and
 * otherwise pushes `nextAttemptAtTimestamp` forward by [LEASE_DURATION_MS]
 * (the lease) and increments `attemptCount`, all inside one transaction so
 * two workers racing the same candidate cannot both win.
 */
async function claimForAttempt(
  db: Firestore,
  ref: DocumentReference<DocumentData>,
  now: Date,
): Promise<ClaimResult> {
  return db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) return { claimed: false, attemptCount: 0 };
    const data = doc.data()!;
    const status = data.status as DeliveryStatus;

    if (status === "delivered" || status === "skipped" || status === "permanentlyFailed") {
      return { claimed: false, attemptCount: data.attemptCount ?? 0, currentStatus: status };
    }

    const dueAt = (data.nextAttemptAtTimestamp?.toDate?.() as Date | undefined) ?? new Date(0);
    if (dueAt.getTime() > now.getTime()) {
      // Either a genuinely-not-yet-due retry backoff, or an unexpired
      // lease held by another worker's in-flight attempt — either way,
      // not claimable right now.
      return { claimed: false, attemptCount: data.attemptCount ?? 0, currentStatus: status };
    }

    const newAttemptCount = (data.attemptCount ?? 0) + 1;
    const leaseExpiry = new Date(now.getTime() + LEASE_DURATION_MS);
    tx.set(
      ref,
      {
        attemptCount: newAttemptCount,
        claimedAt: now.toISOString(),
        nextAttemptAt: leaseExpiry.toISOString(),
        nextAttemptAtTimestamp: leaseExpiry,
        updatedAt: now.toISOString(),
      },
      { merge: true },
    );
    return { claimed: true, attemptCount: newAttemptCount };
  });
}

/**
 * The actual work of one delivery attempt: resolve the Reservation's
 * customer, look up active device tokens, send, record the outcome. Called
 * both by the trigger's fast-path first attempt and by the retry sweep —
 * this is the "pure-ish business function" half of this codebase's
 * established pure-function/thin-trigger-wrapper split
 * (`buildPreorderKdsReleasePatch`/`runPreorderKdsReleaseSweep`), reused
 * verbatim rather than duplicated for the two callers.
 */
async function attemptDelivery(
  db: Firestore,
  ref: DocumentReference<DocumentData>,
  eventType: string,
  reservationId: string,
  sender: PushSender,
  now: Date,
): Promise<ProcessResult> {
  const copy = buildReservationNotificationCopy(eventType);
  if (!copy) {
    // Defensive — every caller already filters non-notifiable events
    // before ever creating a delivery record, so this should not occur
    // in practice.
    await ref.set({ status: "skipped", updatedAt: now.toISOString() }, { merge: true });
    return { processed: true, reason: "not-notifiable" };
  }

  const claim = await claimForAttempt(db, ref, now);
  if (!claim.claimed) {
    return { processed: false, reason: claim.currentStatus ?? "not-due" };
  }

  const reservationDoc = await db.collection("reservations").doc(reservationId).get();
  if (!reservationDoc.exists) {
    await ref.set({ status: "skipped", updatedAt: now.toISOString() }, { merge: true });
    return { processed: true, reason: "reservation-not-found" };
  }
  const customerId = reservationDoc.data()!.customerId as string | undefined;
  if (!customerId) {
    await ref.set({ status: "skipped", updatedAt: now.toISOString() }, { merge: true });
    return { processed: true, reason: "no-customer" };
  }

  // Never cross-customer, never cross-tenant: the query is scoped by
  // `uid` only, and `uid` is always the Reservation's own, server-
  // resolved `customerId` — never anything client-influenced at this
  // layer.
  const tokensSnapshot = await db
    .collection("deviceTokens")
    .where("uid", "==", customerId)
    .where("revokedAt", "==", null)
    .get();
  const tokens = tokensSnapshot.docs
    .map((d) => d.data().token as unknown)
    .filter((t): t is string => typeof t === "string" && t.length > 0);

  if (tokens.length === 0) {
    await ref.set({ status: "skipped", updatedAt: now.toISOString() }, { merge: true });
    return { processed: true, reason: "no-active-tokens" };
  }

  try {
    const result = await sender(tokens, {
      title: copy.title,
      body: copy.body,
      // §13 — deep-link data payload: an internal reservationId only,
      // never a raw URL the client would need to trust/parse.
      data: { reservationId, eventType },
    });

    if (result.invalidTokens.length > 0) {
      const invalid = new Set(result.invalidTokens);
      const nowIso = now.toISOString();
      await Promise.all(
        tokensSnapshot.docs
          .filter((d) => invalid.has(d.data().token as string))
          .map((d) => d.ref.set({ revokedAt: nowIso, updatedAt: nowIso }, { merge: true })),
      );
    }

    await ref.set(
      {
        status: "delivered" satisfies DeliveryStatus,
        tokenCount: tokens.length,
        successCount: result.successCount,
        deliveredAt: now.toISOString(),
        updatedAt: now.toISOString(),
      },
      { merge: true },
    );
    return { processed: true };
  } catch (error: unknown) {
    // Never log the raw tokens array — only a count and the sender's own
    // error code, mirroring `LogRedactor`'s "never log the secret itself"
    // discipline applied to this module's own equivalent (a raw FCM
    // token is exactly as sensitive as an auth token here).
    const errorCode = extractErrorCode(error);
    logger.warn(
      `[reservationNotificationDelivery] send failed for event ${ref.id} ` +
        `(attempt ${claim.attemptCount}/${MAX_ATTEMPTS}, ${tokens.length} token(s)): ${errorCode}`,
    );
    if (claim.attemptCount >= MAX_ATTEMPTS) {
      await ref.set(
        {
          status: "permanentlyFailed" satisfies DeliveryStatus,
          lastErrorCode: errorCode,
          updatedAt: now.toISOString(),
        },
        { merge: true },
      );
      return { processed: false, reason: "permanently-failed" };
    }
    const nextAttemptAt = new Date(now.getTime() + RETRY_BACKOFF_MS);
    await ref.set(
      {
        status: "pending" satisfies DeliveryStatus,
        lastErrorCode: errorCode,
        nextAttemptAt: nextAttemptAt.toISOString(),
        nextAttemptAtTimestamp: nextAttemptAt,
        updatedAt: now.toISOString(),
      },
      { merge: true },
    );
    return { processed: false, reason: "send-failed-will-retry" };
  }
}

function extractErrorCode(error: unknown): string {
  const code = (error as { code?: unknown })?.code;
  if (typeof code === "string" || typeof code === "number") return String(code);
  return "unknown";
}

/**
 * The trigger's own fast-path entry: ensure the delivery record exists,
 * then attempt it immediately — for the common case (first attempt
 * succeeds), this keeps the exact same latency R.3C originally had. Any
 * failure leaves a retryable record for [runReservationNotificationRetrySweep]
 * to pick up later — this function itself never retries in a loop.
 */
export async function processReservationEventForDelivery(
  db: Firestore,
  eventId: string,
  event: Record<string, unknown> | undefined,
  sender: PushSender,
  now: Date = new Date(),
): Promise<ProcessResult> {
  if (!event) return { processed: false, reason: "missing-event" };

  const eventType = event.type as string;
  const copy = buildReservationNotificationCopy(eventType);
  if (!copy) return { processed: false, reason: "not-notifiable" };

  const reservationId = event.reservationId as string | undefined;
  if (!reservationId) return { processed: false, reason: "missing-reservationId" };

  const ref = deliveryCollection(db).doc(eventId);
  await ensureDeliveryRecordExists(ref, { eventId, type: eventType, reservationId }, now);
  return attemptDelivery(db, ref, eventType, reservationId, sender, now);
}

export const onReservationEventCreated = onDocumentCreated(
  "reservationEvents/{eventId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const db = getFirestore();
    await processReservationEventForDelivery(
      db,
      event.params.eventId,
      snapshot.data(),
      defaultSender(),
    );
  },
);

/**
 * Faz R.3C.1 — the actual retry driver. Bounded, indexed candidate query
 * (never an unbounded scan, mirrors `runPreorderKdsReleaseSweep`'s exact
 * shape): every `pending` record whose `nextAttemptAtTimestamp` has
 * elapsed — which covers both a genuinely-due retry backoff *and* a
 * stale/expired lease from a crashed worker's earlier claim, since both
 * are represented by the same field. Requires the composite index
 * `reservationNotificationDeliveries(status ASC, nextAttemptAtTimestamp ASC)`.
 *
 * **Failure isolation**: one candidate's own thrown error is caught and
 * logged, never aborting the rest of the batch — identical reasoning to
 * `runPreorderKdsReleaseSweep`'s own try/catch per candidate.
 */
export async function runReservationNotificationRetrySweep(
  db: Firestore,
  sender: PushSender,
  now: Date = new Date(),
): Promise<number> {
  const dueSnapshot = await deliveryCollection(db)
    .where("status", "==", "pending")
    .where("nextAttemptAtTimestamp", "<=", now)
    .orderBy("nextAttemptAtTimestamp", "asc")
    .limit(SWEEP_BATCH_SIZE)
    .get();

  let attempted = 0;
  for (const doc of dueSnapshot.docs) {
    try {
      const data = doc.data();
      const result = await attemptDelivery(
        db,
        doc.ref,
        data.type as string,
        data.reservationId as string,
        sender,
        now,
      );
      if (result.processed || result.reason === "send-failed-will-retry" || result.reason === "permanently-failed") {
        attempted += 1;
      }
    } catch (error) {
      logger.error(
        `[reservationNotificationRetrySweep] failed processing delivery ${doc.id}`,
        error,
      );
    }
  }
  return attempted;
}

export const reservationNotificationRetrySweep = onSchedule("every 5 minutes", async () => {
  const db = getFirestore();
  const attempted = await runReservationNotificationRetrySweep(db, defaultSender());
  logger.info(`[reservationNotificationRetrySweep] attempted ${attempted} retry candidate(s).`);
});
