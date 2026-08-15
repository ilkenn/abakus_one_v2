/**
 * Table Guest Session policy — single source of truth for the session
 * lifetime and status vocabulary, so `openTableGuestSession` (and any
 * future consumer — a session-refresh endpoint, Phase 3's `orders` rule
 * mirror logic) never hardcodes these independently.
 *
 * **No pre-existing business rule defines a table-visit session duration**
 * (`docs/business_rules.md`/`docs/table_qr_architecture.md` have no such
 * standard as of this writing — confirmed by search before picking a
 * value) — this constant is this phase's own new decision, recorded here
 * and in `docs/business_rules.md`'s BR-TABLE-005 update. 6 hours: long
 * enough to cover a full dine-in visit (a slow, multi-course, multi-order
 * meal) without being effectively unbounded — "the default service window
 * is hour-scale," not day-scale or minute-scale.
 *
 * Overridable via the `TABLE_GUEST_SESSION_TTL_HOURS` environment variable
 * (a real Cloud Functions runtime config value, not a client input) so a
 * local/dev Functions emulator run can use a short TTL to exercise
 * expiry-boundary behavior quickly, without ever touching this file or
 * affecting a real deployed (staging/production) environment, which never
 * sets this variable and always gets the documented 6-hour default. This
 * mirrors `FirebaseAuthEmulatorConfig`'s own "compile-time/environment
 * override, safe default" shape on the Dart side.
 */
const DEFAULT_TABLE_GUEST_SESSION_TTL_HOURS = 6;

function readTtlHours(): number {
  const raw = process.env.TABLE_GUEST_SESSION_TTL_HOURS;
  if (raw === undefined) return DEFAULT_TABLE_GUEST_SESSION_TTL_HOURS;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_TABLE_GUEST_SESSION_TTL_HOURS;
  }
  return parsed;
}

export const TABLE_GUEST_SESSION_TTL_HOURS = readTtlHours();
export const TABLE_GUEST_SESSION_TTL_MS =
  TABLE_GUEST_SESSION_TTL_HOURS * 60 * 60 * 1000;

/** Mirrors the `status` values `tableGuestSessions` documents use — see this phase's own report for why `revoked`/`closed`/`expired` beyond `active` exist even though only `active` is ever written yet (Phase 3 wires the others). */
export type TableGuestSessionStatus = "active" | "closed" | "revoked" | "expired";

export const TABLE_GUEST_SESSION_STATUS: Record<
  TableGuestSessionStatus,
  TableGuestSessionStatus
> = {
  active: "active",
  closed: "closed",
  revoked: "revoked",
  expired: "expired",
};

/**
 * Whether [session] currently represents a live, usable table visit — the
 * exact boundary condition Phase 3's `orders` Security Rule will mirror
 * (`status == 'active' && expiresAt > request.time`). Has **no real
 * caller yet in this phase** (`openTableGuestSession` only ever creates a
 * brand-new session, it never re-reads an existing one) — built and
 * boundary-tested now so Phase 3 can consume it directly rather than
 * re-deriving and re-testing the same logic. `expiresAt` accepts either a
 * `Date` or a Firestore `Timestamp`-shaped value (anything with a
 * `.toDate()` method), matching how a document read back via the Admin
 * SDK actually presents it.
 */
export function isTableGuestSessionActive(
  session: {
    status: string;
    expiresAt: Date | { toDate(): Date };
  },
  now: Date = new Date(),
): boolean {
  if (session.status !== TABLE_GUEST_SESSION_STATUS.active) return false;
  const expiresAt =
    typeof (session.expiresAt as { toDate?: () => Date }).toDate === "function"
      ? (session.expiresAt as { toDate(): Date }).toDate()
      : (session.expiresAt as Date);
  return expiresAt.getTime() > now.getTime();
}
