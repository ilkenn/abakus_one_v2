/**
 * Takeaway Guest Session policy — Faz D.2 (Gel Al QR + Guest Session
 * Backend). Single source of truth for the session lifetime and status
 * vocabulary, mirroring `tableGuestSessionConfig.ts`'s exact shape — a
 * deliberately separate config, not a shared constant, because the two
 * session kinds have genuinely different lifetime needs (see below).
 *
 * **TTL default — RECOMMENDED decision, no prior business rule existed**
 * (`docs/business_rules.md` had no takeaway-guest-session-duration
 * standard before this phase, confirmed by search, same as
 * `tableGuestSessionConfig.ts`'s own precedent for the dine-in case).
 * `tableGuestSessionConfig.ts`'s 6-hour default was sized for "a full
 * dine-in visit (a slow, multi-course, multi-order meal)" — a takeaway
 * QR guest is standing at (or just left) the register for a single
 * checkout, not settling in for a meal. **30 minutes** is this phase's
 * chosen default: generous enough to cover a customer who gets briefly
 * interrupted mid-checkout (a phone call, stepping aside), while not
 * leaving a technical identity's session usable for hours after they've
 * physically left — the anonymous uid itself has no other purpose once
 * the checkout window has passed. Not copied from the table default
 * per this phase's own explicit instruction not to blindly reuse a
 * 6-hour dine-in-scale number for a checkout-scale flow.
 *
 * Overridable via `TAKEAWAY_GUEST_SESSION_TTL_MINUTES` (minutes, not
 * hours — this TTL operates on a much shorter timescale than the table
 * session's hour-scale default) — a real Cloud Functions runtime config
 * value, never a client input, mirroring
 * `TABLE_GUEST_SESSION_TTL_HOURS`'s own environment-override shape.
 */
const DEFAULT_TAKEAWAY_GUEST_SESSION_TTL_MINUTES = 30;

function readTtlMinutes(): number {
  const raw = process.env.TAKEAWAY_GUEST_SESSION_TTL_MINUTES;
  if (raw === undefined) return DEFAULT_TAKEAWAY_GUEST_SESSION_TTL_MINUTES;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_TAKEAWAY_GUEST_SESSION_TTL_MINUTES;
  }
  return parsed;
}

export const TAKEAWAY_GUEST_SESSION_TTL_MINUTES = readTtlMinutes();
export const TAKEAWAY_GUEST_SESSION_TTL_MS =
  TAKEAWAY_GUEST_SESSION_TTL_MINUTES * 60 * 1000;

/**
 * Mirrors `TableGuestSessionStatus`'s own shape. **QR-revocation
 * behavior (Faz D.2 decision)**: revoking/rotating a `takeawayQrCodes`
 * token stops *new* sessions from being opened against it
 * (`resolveTakeawayQrTokenInternal` re-checks the QR document on every
 * call) but never retroactively invalidates a session already granted —
 * a session's own `status`/`expiresAt` here is the sole authority for
 * its own remaining lifetime, exactly mirroring `canReadAsTableGuest`'s
 * "deliberately independent of that session document's continued
 * existence" precedent, applied to the QR side instead of the order
 * side. This is a deliberate security tradeoff, not an oversight:
 * revocation is meant to stop abuse of a specific token going forward
 * (a suspected-compromised or reprinted QR sticker), not to forcibly
 * interrupt a customer already mid-checkout — and this session's own
 * 30-minute default TTL already bounds the exposure window regardless.
 * A future "kill all sessions for this token" admin action would need
 * to explicitly mark matching sessions `revoked`, not just the QR
 * document — no such action exists yet (OPTIONAL finding, this phase's
 * report).
 */
export type TakeawayGuestSessionStatus =
  | "active"
  | "closed"
  | "revoked"
  | "expired";

export const TAKEAWAY_GUEST_SESSION_STATUS: Record<
  TakeawayGuestSessionStatus,
  TakeawayGuestSessionStatus
> = {
  active: "active",
  closed: "closed",
  revoked: "revoked",
  expired: "expired",
};

/**
 * Whether [session] currently represents a live, usable takeaway guest
 * visit — mirrors `isTableGuestSessionActive`'s exact boundary contract
 * (`status == 'active' && expiresAt > now`), operating purely on the
 * session document's own fields — no reference to `takeawayQrCodes` at
 * all, which is the structural proof of this file's own QR-revocation
 * doc comment above.
 */
export function isTakeawayGuestSessionActive(
  session: {
    status: string;
    expiresAt: Date | { toDate(): Date };
  },
  now: Date = new Date(),
): boolean {
  if (session.status !== TAKEAWAY_GUEST_SESSION_STATUS.active) return false;
  const expiresAt =
    typeof (session.expiresAt as { toDate?: () => Date }).toDate === "function"
      ? (session.expiresAt as { toDate(): Date }).toDate()
      : (session.expiresAt as Date);
  return expiresAt.getTime() > now.getTime();
}
