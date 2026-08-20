import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * `completeCustomerProfile` — Customer Registration CR.1 (2026-08-19).
 *
 * Closes the gap the Customer Identity / First Login Registration audit
 * disclosed: phone OTP authentication alone never created either canonical
 * record a real customer needs — `customers/{uid}` (global identity) or
 * `tenantCustomers/{organizationId}_{uid}` (tenant membership) — which is
 * why `requestCustomerPhotoUploadGrant` (and anything else gated on real
 * tenant membership) failed with "You are not a customer of this
 * organization." for every first-time customer. This callable is the one
 * server-authoritative bootstrap path for both records; the client's own
 * `CustomerRegistrationGateway` calls it once, right after a first-time
 * customer completes the "Profilini Tamamla" form.
 *
 * **Never trusts client-supplied identity/authorization data**:
 * - `uid` is always `request.auth.uid`.
 * - `phoneNumber` is always `request.auth.token.phone_number` (the
 *   Firebase-verified OTP claim) — a client-submitted `phoneNumber` is
 *   never even read from `request.data`.
 * - `organizationId` is never accepted from the client at all — see
 *   [SINGLE_TENANT_ORGANIZATION_ID] below.
 * - `accountStatus`, roles, or any claim/permission field are never
 *   accepted from the client — `accountStatus` is always server-set to
 *   `"active"` on first creation (mirrors `CustomerAccountStatus.active`,
 *   `lib/features/crm/domain/segmentation/customer_account_status.dart`)
 *   and never written again by this function on a repeat call.
 *
 * **`organizationId` resolution (temporary, single-tenant)**: Abaküs One
 * has exactly one tenant today (`kSingleTenantOrganizationId`,
 * `lib/core/config/current_organization.dart`). [SINGLE_TENANT_ORGANIZATION_ID]
 * mirrors that same literal by hand across the Dart/TypeScript boundary —
 * the same disclosed, accepted limitation `MAX_ELIGIBLE_PHOTOS` in
 * `customerPhotoUploadGrants.ts` already carries for an equivalent
 * constant. **Future SaaS note**: once Abaküs becomes genuinely
 * multi-tenant, this must be replaced with a real server-side resolution
 * (e.g. an invite/QR-code-driven tenant selection independently verified
 * server-side) — never a client-supplied `organizationId` accepted
 * directly, which is exactly the class of bug `requestCustomerPhotoUploadGrant`
 * (P.4.2A) already had to close once for a different callable.
 *
 * **Idempotent, retry-safe, concurrency-safe, and incapable of duplicating
 * either canonical record — for free, structurally, not via a generated
 * idempotency key**: unlike `customerPhotoUploadGrants.ts` (which mints a
 * NEW document per grant and therefore needs a `requestKey`-derived
 * deterministic id to stay idempotent), both of this function's target
 * documents are already naturally addressed by a fixed, uid-derived path
 * (`customers/{uid}`, `tenantCustomers/{organizationId}_{uid}`) — the
 * same uid can never produce two different documents at those paths, so
 * no `requestKey` is needed or accepted. Concurrent/double-tap safety
 * comes from Firestore's own transaction retry semantics (a transaction
 * whose reads are invalidated by a concurrent commit is automatically
 * retried by the SDK) — the same "reads before writes" transaction
 * discipline already established by `customerPhotoUploadGrants.ts`/
 * `reservationHoldOps.ts` is reused here, not reinvented.
 *
 * **The four repair/idempotency scenarios the audit's own report named,
 * all handled by ONE general algorithm rather than four special cases**:
 * - (A) neither record exists → both created.
 * - (B) `customers/{uid}` already complete, membership missing → ONLY the
 *   membership is created; the already-complete customer record is never
 *   touched.
 * - (C) membership exists, `customers/{uid}` missing or incomplete →
 *   ONLY the customer record is created/repaired from the freshly
 *   submitted (already-validated) form values; membership is left as-is.
 * - (D) both already exist and the customer record is already complete →
 *   zero writes, returns `{ alreadyCompleted: true }`. This function must
 *   never become a general profile-edit endpoint: a repeat call after
 *   completion can never silently change an already-completed profile's
 *   fields, by construction — the write branch for `customers/{uid}` is
 *   only ever reached when [isProfileComplete] is currently `false`.
 *
 * **Completeness definition** (mirrors, field-for-field, the audit's own
 * locked definition and the Dart-side `isCustomerProfileComplete` this
 * function's result is meant to make true): `customers/{uid}` exists,
 * `firstName`/`lastName`/`email` are non-empty, `occupationStatus`/
 * `gender` are valid enum values, the occupation-conditional field
 * (`workplaceName` for `working`, `educationalInstitutionName` for
 * `student`) is present when required, `birthDate` is a valid canonical
 * date (see below), and `profileCompletedAt` is set —
 * `tenantCustomers/{organizationId}_{uid}` existing is a SEPARATE,
 * additional requirement this function also guarantees, never a
 * substitute for the customer-record checks (the audit's own "do NOT
 * decide solely by tenantCustomers presence" instruction).
 *
 * **`birthDate` — CR.1.1 (2026-08-20), required and immutable after first
 * write.** Canonical representation is a plain `"YYYY-MM-DD"` string, never
 * a `Timestamp` — a birth date is a calendar date, not an instant, and a
 * `Timestamp` would force inventing a time-of-day/timezone that doesn't
 * exist and that the locked product decision explicitly forbids. Every
 * call must still submit a valid `birthDate` (`sanitizeBirthDate` runs
 * unconditionally, like every other required field), but the value is
 * only ever merged into the Firestore patch when the existing document
 * does not already carry one — see the write logic below. This is what
 * makes a repeated call structurally incapable of overwriting an
 * already-set `birthDate`, even via the (C) repair path triggered by some
 * unrelated missing field. `customers/{uid}`'s own Firestore rule never
 * allow-lists `birthDate` for client writes either, so this callable
 * (Admin SDK) is the only writer, ever, for both the first write and every
 * subsequent no-op. A future customer-requested correction is intended to
 * go through a separate admin-approval flow, not this callable — see
 * `docs/decisions.md`'s CR.1.1 entry for the documented (not yet built)
 * shape of that flow.
 */

const CUSTOMERS_COLLECTION = "customers";
const TENANT_CUSTOMERS_COLLECTION = "tenantCustomers";

// See this file's own doc comment ("organizationId resolution") — kept in
// sync by hand with lib/core/config/current_organization.dart's
// kSingleTenantOrganizationId, the same cross-language limitation already
// accepted elsewhere in this codebase for an equivalent constant.
const SINGLE_TENANT_ORGANIZATION_ID = "org-1";

// Generous for any real name (including compound/hyphenated Turkish
// names) without being unbounded.
const MAX_NAME_LENGTH = 80;
// RFC 5321 §4.5.3.1.3 — the actual protocol-defined maximum, not an
// arbitrary guess.
const MAX_EMAIL_LENGTH = 254;
// Institution/workplace names can legitimately be long
// ("İstanbul Teknik Üniversitesi Elektrik-Elektronik Mühendisliği
// Bölümü") — a generous, still-bounded cap.
const MAX_INSTITUTION_LENGTH = 200;

// A basic, well-understood "shape" check (local@domain.tld, no
// whitespace) — deliberately not a full RFC 5322 parser; this phase does
// not implement email verification, so format sanity is all that's
// needed or claimed.
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const OCCUPATION_STATUSES = ["working", "student", "other"] as const;
type OccupationStatus = (typeof OCCUPATION_STATUSES)[number];

const GENDERS = ["female", "male", "preferNotToSay"] as const;
type Gender = (typeof GENDERS)[number];

// CR.1.1 — canonical birthDate shape: zero-padded "YYYY-MM-DD", date-only,
// no time/timezone component.
const BIRTH_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
// A calendar sanity bound only — NOT a business/legal minimum-age rule
// (the locked product decision explicitly forbids inventing one). This
// exists solely to reject obviously-garbage input (e.g. a typo'd year
// "0090"), not to gate eligibility.
const MIN_BIRTH_YEAR = 1900;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function sanitizeName(raw: unknown, fieldLabel: string): string {
  if (typeof raw !== "string") invalid(`${fieldLabel} is required.`);
  const trimmed = (raw as string).trim();
  if (trimmed.length === 0) invalid(`${fieldLabel} is required.`);
  if (trimmed.length > MAX_NAME_LENGTH) invalid(`${fieldLabel} is too long.`);
  return trimmed;
}

function sanitizeEmail(raw: unknown): string {
  if (typeof raw !== "string") invalid("email is required.");
  const trimmed = (raw as string).trim().toLowerCase();
  if (trimmed.length === 0) invalid("email is required.");
  if (trimmed.length > MAX_EMAIL_LENGTH) invalid("email is too long.");
  if (!EMAIL_PATTERN.test(trimmed)) invalid("email is not a valid email address.");
  return trimmed;
}

function sanitizeOccupationStatus(raw: unknown): OccupationStatus {
  if (typeof raw !== "string" || !(OCCUPATION_STATUSES as readonly string[]).includes(raw)) {
    invalid("occupationStatus must be one of: working, student, other.");
  }
  return raw as OccupationStatus;
}

function sanitizeGender(raw: unknown): Gender {
  if (typeof raw !== "string" || !(GENDERS as readonly string[]).includes(raw)) {
    invalid("gender must be one of: female, male, preferNotToSay.");
  }
  return raw as Gender;
}

function sanitizeInstitutionField(raw: unknown, fieldLabel: string): string {
  if (typeof raw !== "string") invalid(`${fieldLabel} is required for this occupationStatus.`);
  const trimmed = (raw as string).trim();
  if (trimmed.length === 0) invalid(`${fieldLabel} is required for this occupationStatus.`);
  if (trimmed.length > MAX_INSTITUTION_LENGTH) invalid(`${fieldLabel} is too long.`);
  return trimmed;
}

/**
 * Validates and canonicalizes `birthDate` — see this file's own doc
 * comment ("birthDate — CR.1.1"). Always required, regardless of whether
 * the resulting value ends up written (that decision is made later, once
 * the existing document has been read inside the transaction).
 */
function sanitizeBirthDate(raw: unknown): string {
  if (typeof raw !== "string") invalid("birthDate is required.");
  const trimmed = (raw as string).trim();
  if (!BIRTH_DATE_PATTERN.test(trimmed)) {
    invalid("birthDate must be a canonical YYYY-MM-DD date string.");
  }
  const [yearStr, monthStr, dayStr] = trimmed.split("-");
  const year = Number(yearStr);
  const month = Number(monthStr);
  const day = Number(dayStr);
  const asUtcDate = new Date(Date.UTC(year, month - 1, day));
  // `Date.UTC` silently rolls calendar-impossible dates over (e.g.
  // 2024-02-30 becomes March 1st) instead of throwing — round-tripping
  // the components back out and comparing catches that.
  if (
    asUtcDate.getUTCFullYear() !== year ||
    asUtcDate.getUTCMonth() !== month - 1 ||
    asUtcDate.getUTCDate() !== day
  ) {
    invalid("birthDate is not a valid calendar date.");
  }
  if (year < MIN_BIRTH_YEAR) {
    invalid("birthDate is before the earliest accepted year.");
  }
  const now = new Date();
  const todayCanonical = [
    now.getUTCFullYear().toString().padStart(4, "0"),
    (now.getUTCMonth() + 1).toString().padStart(2, "0"),
    now.getUTCDate().toString().padStart(2, "0"),
  ].join("-");
  // Zero-padded YYYY-MM-DD strings compare lexicographically exactly like
  // dates compare chronologically — no `Date` object needed for this
  // check, so no timezone semantics enter it at all.
  if (trimmed > todayCanonical) {
    invalid("birthDate cannot be in the future.");
  }
  return trimmed;
}

interface SanitizedProfileInput {
  firstName: string;
  lastName: string;
  email: string;
  occupationStatus: OccupationStatus;
  workplaceName: string | null;
  educationalInstitutionName: string | null;
  gender: Gender;
  birthDate: string;
}

function sanitizeInput(data: Record<string, unknown> | undefined): SanitizedProfileInput {
  const firstName = sanitizeName(data?.firstName, "firstName");
  const lastName = sanitizeName(data?.lastName, "lastName");
  const email = sanitizeEmail(data?.email);
  const occupationStatus = sanitizeOccupationStatus(data?.occupationStatus);
  const gender = sanitizeGender(data?.gender);
  const birthDate = sanitizeBirthDate(data?.birthDate);

  let workplaceName: string | null = null;
  let educationalInstitutionName: string | null = null;
  if (occupationStatus === "working") {
    workplaceName = sanitizeInstitutionField(data?.workplaceName, "workplaceName");
  } else if (occupationStatus === "student") {
    educationalInstitutionName = sanitizeInstitutionField(
      data?.educationalInstitutionName,
      "educationalInstitutionName",
    );
  }
  // occupationStatus === "other" — both stay null regardless of whatever
  // the client sent for either field; a client-supplied workplaceName/
  // educationalInstitutionName is never read at all in this branch
  // (locked requirement: "other clears/rejects irrelevant conditional
  // fields consistently").

  return {
    firstName,
    lastName,
    email,
    occupationStatus,
    workplaceName,
    educationalInstitutionName,
    gender,
    birthDate,
  };
}

function deriveDisplayName(firstName: string, lastName: string): string {
  return `${firstName} ${lastName}`.trim();
}

/**
 * The one, server-side-and-client-side-shared definition of "complete" —
 * see this file's own doc comment. Exported so tests can assert on it
 * directly, mirroring `customerPhotoUploadGrants.ts`'s own exported-
 * constants convention.
 */
function isProfileComplete(data: FirebaseFirestore.DocumentData | undefined): boolean {
  if (!data) return false;
  if (typeof data.firstName !== "string" || data.firstName.trim().length === 0) return false;
  if (typeof data.lastName !== "string" || data.lastName.trim().length === 0) return false;
  if (typeof data.email !== "string" || data.email.trim().length === 0) return false;
  if (
    typeof data.occupationStatus !== "string" ||
    !(OCCUPATION_STATUSES as readonly string[]).includes(data.occupationStatus)
  ) {
    return false;
  }
  if (typeof data.gender !== "string" || !(GENDERS as readonly string[]).includes(data.gender)) return false;
  if (typeof data.birthDate !== "string" || !BIRTH_DATE_PATTERN.test(data.birthDate)) return false;
  if (!data.profileCompletedAt) return false;
  if (
    data.occupationStatus === "working" &&
    (typeof data.workplaceName !== "string" || data.workplaceName.trim().length === 0)
  ) {
    return false;
  }
  if (
    data.occupationStatus === "student" &&
    (typeof data.educationalInstitutionName !== "string" || data.educationalInstitutionName.trim().length === 0)
  ) {
    return false;
  }
  return true;
}

interface CompleteCustomerProfileResult {
  alreadyCompleted: boolean;
  organizationId: string;
}

export const completeCustomerProfile = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<CompleteCustomerProfileResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Profile completion requires a real, phone-verified customer identity.",
      );
    }
    const phoneNumber = request.auth.token.phone_number;
    if (typeof phoneNumber !== "string" || phoneNumber.length === 0) {
      throw new HttpsError("failed-precondition", "The authenticated session has no verified phone number.");
    }
    const uid = request.auth.uid;

    // Never client-supplied — see this file's own doc comment.
    const organizationId = SINGLE_TENANT_ORGANIZATION_ID;

    const input = sanitizeInput(request.data as Record<string, unknown> | undefined);

    const db = getFirestore();
    const customerRef = db.collection(CUSTOMERS_COLLECTION).doc(uid);
    const membershipRef = db.collection(TENANT_CUSTOMERS_COLLECTION).doc(`${organizationId}_${uid}`);

    const result = await db.runTransaction(async (tx): Promise<CompleteCustomerProfileResult> => {
      // Reads first, always — mirrors this codebase's established
      // "reads before writes" transaction discipline
      // (customerPhotoUploadGrants.ts, reservationHoldOps.ts).
      const customerSnap = await tx.get(customerRef);
      const membershipSnap = await tx.get(membershipRef);
      const now = Timestamp.now();

      const customerAlreadyComplete = isProfileComplete(customerSnap.data());
      const membershipAlreadyExists = membershipSnap.exists;

      if (customerAlreadyComplete && membershipAlreadyExists) {
        // (D) — idempotent no-op.
        return { alreadyCompleted: true, organizationId };
      }

      if (!customerAlreadyComplete) {
        // (A)/(C) — create or repair. Never reached when the customer is
        // already complete (branch above), so an already-completed
        // profile's fields are never overwritten by a repeat call.
        const displayName = deriveDisplayName(input.firstName, input.lastName);
        const patch: FirebaseFirestore.DocumentData = {
          uid,
          firstName: input.firstName,
          lastName: input.lastName,
          displayName,
          email: input.email,
          phoneNumber,
          occupationStatus: input.occupationStatus,
          workplaceName: input.workplaceName,
          educationalInstitutionName: input.educationalInstitutionName,
          gender: input.gender,
          profileCompletedAt: now,
          updatedAt: now,
        };

        // CR.1.1 — birthDate immutability. A (C)-repair call can be
        // triggered by some OTHER field being missing/invalid even when
        // birthDate was already correctly set on a prior call; the patch
        // must omit the `birthDate` key entirely in that case so
        // `tx.update` (which only ever touches keys present in the patch)
        // leaves the existing value completely untouched. Only when the
        // existing document has no valid canonical birthDate yet does the
        // freshly-validated `input.birthDate` get included — the one and
        // only first write.
        const existingBirthDate = customerSnap.data()?.birthDate;
        const birthDateAlreadySet =
          typeof existingBirthDate === "string" && BIRTH_DATE_PATTERN.test(existingBirthDate);
        if (!birthDateAlreadySet) {
          patch.birthDate = input.birthDate;
        }

        if (customerSnap.exists) {
          tx.update(customerRef, patch);
        } else {
          tx.set(customerRef, { ...patch, accountStatus: "active", createdAt: now });
        }
      }

      if (!membershipAlreadyExists) {
        // (A)/(B) — create the missing membership, independent of
        // whichever branch above did or didn't run.
        tx.set(membershipRef, { organizationId, uid, createdAt: now });
      }

      return { alreadyCompleted: false, organizationId };
    });

    logger.info("[completeCustomerProfile] profile bootstrap resolved", {
      uid,
      organizationId,
      alreadyCompleted: result.alreadyCompleted,
    });

    return result;
  },
);

export {
  SINGLE_TENANT_ORGANIZATION_ID,
  CUSTOMERS_COLLECTION,
  TENANT_CUSTOMERS_COLLECTION,
  isProfileComplete,
  sanitizeInput,
  deriveDisplayName,
  OCCUPATION_STATUSES,
  GENDERS,
};
export type { OccupationStatus, Gender, SanitizedProfileInput, CompleteCustomerProfileResult };
