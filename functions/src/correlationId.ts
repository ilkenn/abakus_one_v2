import { randomUUID } from "crypto";

/**
 * AP-2 Stage B, Correction #7 — the canonical correlation id for an audit
 * event/mutation is always backend-generated, never accepted from a client
 * as authority. A client may still supply its own `clientRequestId` (an
 * idempotency-key-shaped value it can use to correlate its own retries with
 * a server response) — sanitized and length-bounded here, carried alongside
 * the canonical id in an audit event, never used as a substitute for it.
 */
export function generateCorrelationId(): string {
  return `corr_${randomUUID()}`;
}

const CLIENT_REQUEST_ID_MAX_LENGTH = 128;
const CLIENT_REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * Validates and returns [raw] as a safe `clientRequestId`, or `null` if it
 * is absent, the wrong type, too long, or contains anything outside a
 * bounded alphanumeric/dash/underscore charset — structurally excludes
 * PII/secrets (an email, phone number, or bearer token cannot match this
 * pattern) rather than relying on the caller never sending one.
 */
export function sanitizeClientRequestId(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  if (raw.length === 0 || raw.length > CLIENT_REQUEST_ID_MAX_LENGTH) return null;
  if (!CLIENT_REQUEST_ID_PATTERN.test(raw)) return null;
  return raw;
}
