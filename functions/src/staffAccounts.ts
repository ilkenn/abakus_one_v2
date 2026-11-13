import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import type { UserRecord } from "firebase-admin/auth";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";
import {
  VALID_ROLES,
  markClaimsRevoked,
  membershipId,
  resyncClaimsForUid,
} from "./staffMembership";
import type { MembershipDoc, MembershipRole, MembershipStatus } from "./staffMembership";

/**
 * ADR-085 (revised 2026-11-13) — staff accounts are created and managed
 * directly from the panel ("Personel Ekle"), and staff sign in with phone
 * number + password on the phone and on the Windows POS.
 *
 * **One person, one account.** Firebase Auth has no phone+password
 * provider, so a staff account carries BOTH the phone number (so the same
 * person's customer SMS sign-in lands on the same uid) and a hidden
 * technical e-mail derived from that number ([staffLoginEmailForPhone])
 * with the password. The client derives the same e-mail from the typed
 * phone number (`lib/features/auth/domain/staff_login_email.dart`) — the
 * two derivations must stay identical. Nobody ever sees or types it. If an
 * account with the number already exists (the person was a customer), the
 * e-mail and password are added to it: their customer history is kept.
 *
 * **Who may manage whom** ([resolveStaffScope]):
 * - an admin/owner (`manageStaffAccounts`) manages every account in the
 *   organization except accounts holding `admin` or `tenantOwner` (no
 *   peer or superior); granting `admin` additionally needs
 *   `manageStaffAdminRole`; `tenantOwner` is never granted here;
 * - a manager (`manageStaffRoles` + `manageStaffBranchAccess`) manages
 *   only accounts whose roles are all below the manager tier and whose
 *   branches are all their own (at least one), before and after the change;
 * - nobody manages their own account here.
 *
 * Every mutation writes an `auditEvents` record in the same transaction as
 * the membership change. A password never reaches Firestore or a log.
 */

/** Roles a manager may manage: those below the manager tier. */
const BRANCH_MANAGEABLE_ROLES: ReadonlySet<MembershipRole> = new Set([
  "staff",
  "cashier",
  "packingLead",
  "courier",
]);

/** Roles whose holders are off-limits to every scope (no peer/superior). */
const PROTECTED_ROLES: ReadonlySet<MembershipRole> = new Set(["admin", "tenantOwner"]);

const MIN_PASSWORD_LENGTH = 8;
const MAX_PASSWORD_LENGTH = 128;
const MAX_NAME_LENGTH = 60;

/** E.164: a plus sign, a non-zero country digit, 8 to 15 digits in total. */
const E164_PATTERN = /^\+[1-9]\d{7,14}$/;

/**
 * The hidden sign-in e-mail of the staff account for [phoneNumber]
 * (`+905551234567` → `905551234567@staff-login.abakus.invalid`). The
 * `.invalid` top-level domain is reserved (RFC 2606): mail to it can never
 * be delivered to anyone.
 */
export function staffLoginEmailForPhone(phoneNumber: string): string {
  return `${phoneNumber.replace(/^\+/, "")}@staff-login.abakus.invalid`;
}

type StaffScope =
  | { kind: "organization"; canGrantAdmin: boolean }
  | { kind: "branch"; branches: ReadonlySet<string> };

interface AccessShape {
  roles: MembershipRole[];
  branchAccess: string[];
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function denied(message: string): never {
  throw new HttpsError("permission-denied", message);
}

function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) invalid(`${field} is required.`);
  return (value as string).trim();
}

function requireName(value: unknown, field: string): string {
  const name = requireNonEmptyString(value, field);
  if (name.length > MAX_NAME_LENGTH) invalid(`${field} must be at most ${MAX_NAME_LENGTH} characters.`);
  return name;
}

function requirePhoneNumber(value: unknown): string {
  const phone = requireNonEmptyString(value, "phoneNumber");
  if (!E164_PATTERN.test(phone)) invalid("phoneNumber must be in E.164 form, e.g. +905551234567.");
  return phone;
}

function requirePassword(value: unknown): string {
  if (typeof value !== "string" || value.length < MIN_PASSWORD_LENGTH || value.length > MAX_PASSWORD_LENGTH) {
    invalid(`password must be ${MIN_PASSWORD_LENGTH}–${MAX_PASSWORD_LENGTH} characters.`);
  }
  return value as string;
}

function requireRoles(value: unknown): MembershipRole[] {
  if (!Array.isArray(value) || value.length === 0) invalid("roles must contain at least one role.");
  const roles = [...new Set(value as unknown[])];
  for (const role of roles) {
    if (typeof role !== "string" || !VALID_ROLES.includes(role as MembershipRole)) {
      invalid(`role must be one of: ${VALID_ROLES.join(", ")}.`);
    }
  }
  return roles as MembershipRole[];
}

function requireBranches(value: unknown): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.some((v) => typeof v !== "string" || v.length === 0)) {
    invalid("branchAccess must be a list of non-empty strings.");
  }
  return [...new Set(value as string[])];
}

async function holdsPermission(
  request: CallableRequest,
  organizationId: string,
  permission: Parameters<typeof requireStaffPermission>[2],
): Promise<boolean> {
  try {
    await requireStaffPermission(request, organizationId, permission);
    return true;
  } catch (error) {
    if (error instanceof HttpsError && error.code === "permission-denied") return false;
    throw error;
  }
}

/** See the module comment. Throws `permission-denied` for anyone else. */
async function resolveStaffScope(request: CallableRequest, organizationId: string): Promise<StaffScope> {
  if (await holdsPermission(request, organizationId, "manageStaffAccounts")) {
    return {
      kind: "organization",
      canGrantAdmin: await holdsPermission(request, organizationId, "manageStaffAdminRole"),
    };
  }
  await requireStaffPermission(request, organizationId, "manageStaffRoles");
  await requireStaffPermission(request, organizationId, "manageStaffBranchAccess");
  const byOrg = request.auth?.token?.branchAccess as Record<string, unknown> | undefined;
  const own = byOrg?.[organizationId];
  const branches = new Set(Array.isArray(own) ? own.filter((b): b is string => typeof b === "string") : []);
  return { kind: "branch", branches };
}

/** Whether [scope] may hold an account shaped like [access] (checked before AND after a change). */
function assertWithinScope(scope: StaffScope, access: AccessShape): void {
  if (scope.kind === "organization") {
    if (access.roles.includes("tenantOwner")) denied("The owner role cannot be managed from the panel.");
    if (access.roles.includes("admin") && !scope.canGrantAdmin) denied("Granting the admin role requires manageStaffAdminRole.");
    return;
  }
  const ok =
    access.branchAccess.length > 0 &&
    access.roles.every((role) => BRANCH_MANAGEABLE_ROLES.has(role)) &&
    access.branchAccess.every((branchId) => scope.branches.has(branchId));
  if (!ok) {
    denied("A manager can manage only cashier/courier-level staff, and only in their own branches.");
  }
}

/** An existing account is off-limits if it holds a protected role (no peer/superior), for every scope. */
function assertTargetNotProtected(access: AccessShape): void {
  if (access.roles.some((role) => PROTECTED_ROLES.has(role))) {
    denied("Admin and owner accounts cannot be managed by another staff member.");
  }
}

async function assertBranchesBelongToOrganization(organizationId: string, branchAccess: string[]): Promise<void> {
  const db = getFirestore();
  for (const branchId of branchAccess) {
    const branch = await db.collection("branches").doc(branchId).get();
    if (!branch.exists || branch.data()?.organizationId !== organizationId) {
      invalid(`Branch "${branchId}" does not belong to this organization.`);
    }
  }
}

async function findUserByPhone(phoneNumber: string): Promise<UserRecord | null> {
  try {
    return await getAuth().getUserByPhoneNumber(phoneNumber);
  } catch (error) {
    if ((error as { code?: string }).code === "auth/user-not-found") return null;
    throw error;
  }
}

function callerRoles(request: CallableRequest, organizationId: string): string[] {
  const roles = (request.auth?.token?.roles as Record<string, unknown> | undefined)?.[organizationId];
  return Array.isArray(roles) ? roles.filter((r): r is string => typeof r === "string") : [];
}

/**
 * "Personel Ekle" — creates an active staff account in one step: name,
 * phone number, password, roles, branches. Reuses an existing account
 * with that number (adding the sign-in e-mail and password) so a
 * customer's history is kept. Refuses a number that is already staff in
 * this organization (use [updateStaffMember]/[setStaffPassword] instead).
 */
export const createStaffAccount = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const firstName = requireName(data.firstName, "firstName");
    const lastName = requireName(data.lastName, "lastName");
    const phoneNumber = requirePhoneNumber(data.phoneNumber);
    const password = requirePassword(data.password);
    const roles = requireRoles(data.roles);
    const branchAccess = requireBranches(data.branchAccess);

    if (request.auth.token?.phone_number === phoneNumber) denied("You cannot add your own phone number.");
    const scope = await resolveStaffScope(request, organizationId);
    assertWithinScope(scope, { roles, branchAccess });
    await assertBranchesBelongToOrganization(organizationId, branchAccess);

    const db = getFirestore();
    const email = staffLoginEmailForPhone(phoneNumber);
    const displayName = `${firstName} ${lastName}`;
    const existing = await findUserByPhone(phoneNumber);
    let uid: string;
    if (existing) {
      if (existing.uid === request.auth.uid) denied("You cannot add your own phone number.");
      const membership = await db.collection("memberships").doc(membershipId(organizationId, existing.uid)).get();
      if (membership.exists) {
        throw new HttpsError("already-exists", "This phone number already belongs to a staff member of this organization.");
      }
      if (existing.email && existing.email !== email) {
        throw new HttpsError("failed-precondition", "This account already signs in with a different e-mail address.");
      }
      await getAuth().updateUser(existing.uid, { email, password, displayName: existing.displayName ?? displayName });
      uid = existing.uid;
    } else {
      uid = (await getAuth().createUser({ phoneNumber, email, password, displayName })).uid;
    }

    const now = new Date();
    const ref = db.collection("memberships").doc(membershipId(organizationId, uid));
    const doc: MembershipDoc = {
      organizationId,
      uid,
      roles,
      branchAccess,
      restaurantAccess: [],
      status: "active",
      createdAt: now,
      updatedAt: now,
      version: 1,
      firstName,
      lastName,
      phoneNumber,
    };
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) {
        throw new HttpsError("already-exists", "This phone number already belongs to a staff member of this organization.");
      }
      tx.set(ref, doc);
      writeAuditEvent({
        tx,
        db,
        eventId: `${ref.id}-created-${now.getTime()}`,
        organizationId,
        type: "staff.accountCreated",
        targetRef: ref.path,
        newValue: { roles, branchAccess, status: "active", reusedExistingAccount: existing !== null },
        actorType: "staff",
        actorUid: request.auth!.uid,
        actorRoles: callerRoles(request, organizationId),
        correlationId: generateCorrelationId(),
        now: Timestamp.fromDate(now),
      });
    });
    await resyncClaimsForUid(uid);

    return { organizationId, uid, reusedExistingAccount: existing !== null };
  },
);

async function loadTargetMembership(organizationId: string, targetUid: string) {
  const ref = getFirestore().collection("memberships").doc(membershipId(organizationId, targetUid));
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "No staff member found for this account in this organization.");
  const doc = snap.data() as MembershipDoc;
  if (doc.status === "archived") throw new HttpsError("failed-precondition", "This staff member is archived.");
  return { ref, doc };
}

/**
 * Sets a staff member's password. Ends every open session of that account
 * (refresh tokens revoked; staff claims stamped stale). An account created
 * before ADR-085 that has a phone number but no sign-in e-mail gets one.
 */
export const setStaffPassword = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const targetUid = requireNonEmptyString(data.targetUid, "targetUid");
    const password = requirePassword(data.password);

    if (targetUid === request.auth.uid) denied("Change your own password from your profile.");
    const scope = await resolveStaffScope(request, organizationId);
    const { ref, doc } = await loadTargetMembership(organizationId, targetUid);
    assertTargetNotProtected(doc);
    assertWithinScope(scope, doc);

    const user = await getAuth().getUser(targetUid);
    const update: { password: string; email?: string } = { password };
    if (!user.email && user.phoneNumber) update.email = staffLoginEmailForPhone(user.phoneNumber);
    await getAuth().updateUser(targetUid, update);
    await getAuth().revokeRefreshTokens(targetUid);
    await markClaimsRevoked(targetUid);

    const db = getFirestore();
    const now = new Date();
    await db.runTransaction(async (tx) => {
      writeAuditEvent({
        tx,
        db,
        eventId: `${ref.id}-password-${now.getTime()}`,
        organizationId,
        type: "staff.passwordSet",
        targetRef: ref.path,
        actorType: "staff",
        actorUid: request.auth!.uid,
        actorRoles: callerRoles(request, organizationId),
        correlationId: generateCorrelationId(),
        now: Timestamp.fromDate(now),
      });
    });

    return { organizationId, targetUid, passwordSet: true };
  },
);

const EDITABLE_STATUSES: readonly MembershipStatus[] = ["active", "suspended"];

/**
 * Changes a staff member's roles, branches, active/suspended status and/or
 * name. Scope is checked on the account as it is and as it would become.
 * Any narrowing (a role or branch removed, or suspension) stamps the staff
 * claims stale so the change takes effect at once.
 */
export const updateStaffMember = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const targetUid = requireNonEmptyString(data.targetUid, "targetUid");

    if (targetUid === request.auth.uid) denied("A staff member cannot change their own access.");
    const scope = await resolveStaffScope(request, organizationId);
    const { ref, doc } = await loadTargetMembership(organizationId, targetUid);
    assertTargetNotProtected(doc);
    assertWithinScope(scope, doc);

    const roles = data.roles === undefined ? doc.roles : requireRoles(data.roles);
    const branchAccess = data.branchAccess === undefined ? doc.branchAccess : requireBranches(data.branchAccess);
    let status = doc.status;
    if (data.status !== undefined) {
      if (!EDITABLE_STATUSES.includes(data.status as MembershipStatus)) {
        invalid(`status must be one of: ${EDITABLE_STATUSES.join(", ")}.`);
      }
      status = data.status as MembershipStatus;
    }
    const firstName = data.firstName === undefined ? doc.firstName : requireName(data.firstName, "firstName");
    const lastName = data.lastName === undefined ? doc.lastName : requireName(data.lastName, "lastName");
    assertWithinScope(scope, { roles, branchAccess });
    await assertBranchesBelongToOrganization(organizationId, branchAccess);

    const narrowed =
      doc.roles.some((r) => !roles.includes(r)) ||
      doc.branchAccess.some((b) => !branchAccess.includes(b)) ||
      (doc.status === "active" && status !== "active");

    const db = getFirestore();
    const now = new Date();
    const version = (doc.version ?? 1) + 1;
    await db.runTransaction(async (tx) => {
      const update: Record<string, unknown> = { roles, branchAccess, status, updatedAt: now, version };
      if (firstName !== undefined) update.firstName = firstName;
      if (lastName !== undefined) update.lastName = lastName;
      tx.update(ref, update);
      writeAuditEvent({
        tx,
        db,
        eventId: `${ref.id}-updated-v${version}`,
        organizationId,
        type: "staff.memberUpdated",
        targetRef: ref.path,
        previousValue: { roles: doc.roles, branchAccess: doc.branchAccess, status: doc.status },
        newValue: { roles, branchAccess, status },
        actorType: "staff",
        actorUid: request.auth!.uid,
        actorRoles: callerRoles(request, organizationId),
        correlationId: generateCorrelationId(),
        now: Timestamp.fromDate(now),
      });
    });
    await resyncClaimsForUid(targetUid);
    if (narrowed) await markClaimsRevoked(targetUid);

    return { organizationId, targetUid, roles, branchAccess, status };
  },
);
