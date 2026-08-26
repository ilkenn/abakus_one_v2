import { createHash } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Firestore, Timestamp } from "firebase-admin/firestore";
import { resolveActiveTakeawayBranch } from "./takeawayScope";
import {
  loadCanonicalMenuProduct,
  loadCanonicalBowlIngredient,
  loadCanonicalChannelPricingPolicy,
  type CanonicalMenuProduct,
} from "./takeawayCatalog";
import {
  resolveProductUnitPriceMinorUnits,
  resolveBowlUnitAdjustmentMinorUnits,
  buildOrderLine,
  computeOrderPriceBreakdown,
  type ComputedOrderLine,
  type OrderLineModifierInput,
} from "./takeawayPricing";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "./orderPricingAuthority";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
  type LoyaltyLedgerEntry,
} from "./loyaltyLedger";
import {
  loyaltyPolicyDocRef,
  loyaltyPolicyBootstrapRef,
  readLoyaltyPolicyInTransaction,
  writeDefaultLoyaltyPolicyInTransaction,
  type LoyaltyPolicy,
} from "./loyaltyPolicy";
import { calculateBoncukRedemption, resolveAccountForRedemption } from "./loyaltyRedemption";
import type { LoyaltyAccountData } from "./getCustomerLoyaltySnapshot";
import {
  boncukError,
  sanitizeRequestedBoncukAmount,
  sanitizeSelectedRewardId,
  sanitizeSelectedCampaignId,
  type SelectedBenefitType,
} from "./boncukRedemptionErrors";
import { enforceBenefitExclusivity } from "./benefitExclusivity";
import {
  loadLoyaltyRewardForRedemption,
  resolveCatalogRewardRedemption,
} from "./resolveCatalogRewardRedemption";
import {
  isRewardCurrentlyValid,
  loyaltyRewardCatalogVersionDocId,
  type LoyaltyRewardCatalogEntry,
  type CanonicalCommercialChannel,
} from "./loyaltyRewardCatalog";
import {
  CAMPAIGNS_COLLECTION,
  parseCampaignDefinition,
  type CampaignDefinition,
  type CampaignOrderSnapshot,
} from "./campaignEngine";
import { isCampaignScheduleCurrentlyOpen, DEFAULT_ORGANIZATION_TIMEZONE } from "./campaignScheduling";
import {
  resolveCampaignDiscount,
  type CampaignPriceableLine,
} from "./campaignPricing";
import { reserveCampaignUsage } from "./campaignUsage";

/**
 * Boncuk Loyalty P7-C.1 (2026-08-24) — the real, server-derived commercial
 * channel of every order this callable ever creates. A `CanonicalCommercialChannel`
 * literal (never read from client input), used to validate a selected
 * catalog reward's own `eligibleChannels` and to snapshot the actual
 * redemption channel onto the order document, immutably.
 */
const TAKEAWAY_COMMERCIAL_CHANNEL: CanonicalCommercialChannel = "takeaway";

/**
 * Server-authoritative takeaway order creation — Faz D.3. The one
 * callable both takeaway scenarios (QR guest, authenticated app customer)
 * submit through, sharing the exact same pricing/validation pipeline
 * (this phase's own "duplicate business logic oluşturma" instruction) —
 * everything from here down is written once, not twice.
 *
 * **Backend is the sole authority** for organization/restaurant/branch
 * scope, product identity/availability/category/price, modifier
 * identity/price, channel-adjusted pricing, computed totals, pickup
 * semantics, and initial status. A client-submitted price of any kind
 * (unitPrice/subtotal/grandTotal/anything else) is never read by this
 * function at all — there is no field in the accepted request shape for
 * one, so there is nothing to "ignore," only nothing to trust in the
 * first place.
 *
 * Mirrors `SubmitCustomerOrder`/`CartToOrderMapper`'s exact document
 * shape (`OrderFirestoreMapper.toFirestore`) so an order created here
 * reads back identically through the existing Dart
 * `OrderFirestoreMapper.fromFirestore` — this is a new authoritative
 * writer, not a new document shape.
 *
 * Mirrors `orderStatus.ts`'s own `created -> pendingConfirmation`
 * pre-transition: the document is written directly at
 * `pendingConfirmation` with one `statusHistory` entry (actor
 * `customer`), exactly like `SubmitCustomerOrder.call()` does client-side
 * before ever persisting — `onOrderCreated`'s trigger correctly no-ops
 * for these orders (its own doc comment already documents this "already
 * past created" case).
 */

// -----------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------

/** Mirrors `TaxPolicy.defaultRate` (`TaxRate.fromBasisPoints(1000)`, 10%). */
const TAKEAWAY_TAX_BASIS_POINTS = 1000;

/** Mirrors `PickupTimePolicy.minimumLeadTime` (`Duration(minutes: 20)`). */
const PICKUP_MINIMUM_LEAD_MINUTES = 20;

/** New server-side safety policy this phase adds — `OrderLine.create` itself has no upper bound in Dart; an authoritative backend does need one against an abusive/mistaken request. */
const MAX_ITEM_QUANTITY = 20;
const MAX_ITEMS_PER_ORDER = 50;
const MAX_CONTACT_FIELD_LENGTH = 100;
const MAX_SUBMISSION_KEY_LENGTH = 200;

/** Blocks the two characters an HTML/script-injection payload structurally needs, plus ASCII control characters — a genuine structural safety net (contact validation requirement), not a full sanitizer library (no new dependency). */
const DISALLOWED_CONTACT_CHARACTERS = /[<>]/;

// -----------------------------------------------------------------------
// Request shape
// -----------------------------------------------------------------------

export interface RawModifierSelection {
  groupId: unknown;
  optionId: unknown;
}

export interface RawProductItem {
  kind: "product";
  productId: unknown;
  quantity: unknown;
  selectedModifiers?: unknown;
  note?: unknown;
}

export interface RawBowlItem {
  kind: "bowl";
  quantity: unknown;
  ingredientIds: unknown;
  note?: unknown;
}

export type RawItem = RawProductItem | RawBowlItem;

// -----------------------------------------------------------------------
// Validation helpers
// -----------------------------------------------------------------------

export function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

// Boncuk Loyalty P5-B (2026-08-24) — `BONCUK_REDEMPTION_ERROR_REASONS`/
// `BoncukRedemptionErrorReason`/`boncukError` moved to the new, neutral
// `boncukRedemptionErrors.ts` module (imported above) so
// `submitDeliveryOrder.ts` can reuse the exact same stable-reason
// vocabulary rather than a second, private copy. Behavior unchanged.

/** Trim, length-cap, and reject disallowed characters (see `DISALLOWED_CONTACT_CHARACTERS`). */
function sanitizeContactField(raw: unknown, fieldName: string): string {
  if (typeof raw !== "string") invalid(`${fieldName} is required.`);
  const trimmed = (raw as string).trim();
  if (trimmed.length === 0) invalid(`${fieldName} must not be empty.`);
  if (trimmed.length > MAX_CONTACT_FIELD_LENGTH) invalid(`${fieldName} is too long.`);
  if (DISALLOWED_CONTACT_CHARACTERS.test(trimmed)) {
    invalid(`${fieldName} contains disallowed characters.`);
  }
  return trimmed;
}

/** Loose, structural E.164-ish check — never the order's authorization source (identity always comes from Firebase Auth, never from this field). */
function sanitizePhone(raw: unknown): string {
  const trimmed = sanitizeContactField(raw, "contactPhone");
  const digitsOnly = trimmed.replace(/[\s\-().]/g, "");
  if (!/^\+?[0-9]{7,15}$/.test(digitsOnly)) {
    invalid("contactPhone is not a valid phone number.");
  }
  return trimmed;
}

function sanitizeSubmissionKey(raw: unknown): string {
  if (typeof raw !== "string" || raw.length === 0) invalid("submissionKey is required.");
  if (raw.length > MAX_SUBMISSION_KEY_LENGTH) invalid("submissionKey is too long.");
  return raw;
}

// Boncuk Loyalty P5-B — `sanitizeRequestedBoncukAmount` moved to
// `boncukRedemptionErrors.ts` (imported above), reused verbatim by
// `submitDeliveryOrder.ts`. Behavior unchanged.

export function parseItems(raw: unknown): RawItem[] {
  if (!Array.isArray(raw) || raw.length === 0) invalid("items must be a non-empty array.");
  if (raw.length > MAX_ITEMS_PER_ORDER) invalid("too many items in one order.");
  return (raw as Record<string, unknown>[]).map((item) => {
    if (item.kind === "product") {
      return {
        kind: "product",
        productId: item.productId,
        quantity: item.quantity,
        selectedModifiers: item.selectedModifiers,
        note: item.note,
      };
    }
    if (item.kind === "bowl") {
      return {
        kind: "bowl",
        quantity: item.quantity,
        ingredientIds: item.ingredientIds,
        note: item.note,
      };
    }
    return invalid('each item must have kind "product" or "bowl".');
  });
}

export function requireValidQuantity(raw: unknown, context: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw)) {
    invalid(`${context}: quantity must be an integer.`);
  }
  const quantity = raw as number;
  if (quantity <= 0) invalid(`${context}: quantity must be positive.`);
  if (quantity > MAX_ITEM_QUANTITY) invalid(`${context}: quantity exceeds the maximum allowed.`);
  return quantity;
}

// -----------------------------------------------------------------------
// Catalog-backed line building
// -----------------------------------------------------------------------

export async function resolveProductModifiers(
  product: CanonicalMenuProduct,
  raw: unknown,
): Promise<OrderLineModifierInput[]> {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) invalid(`product "${product.id}": selectedModifiers must be an array.`);

  const resolved: OrderLineModifierInput[] = [];
  for (const entry of raw as RawModifierSelection[]) {
    const groupId = entry?.groupId;
    const optionId = entry?.optionId;
    if (typeof groupId !== "string" || typeof optionId !== "string") {
      invalid(`product "${product.id}": each selectedModifiers entry needs groupId/optionId.`);
    }
    const group = product.modifierGroups.find((g) => g.id === groupId);
    if (!group) {
      invalid(`product "${product.id}": modifier group "${groupId}" does not exist on this product.`);
    }
    const option = group!.options.find((o) => o.id === optionId);
    if (!option) {
      invalid(
        `product "${product.id}": modifier option "${optionId}" does not exist in group "${groupId}".`,
      );
    }
    if (!option!.isAvailable) {
      invalid(`product "${product.id}": modifier option "${optionId}" is not available.`);
    }
    resolved.push({
      groupId: group!.id,
      groupName: group!.name,
      optionId: option!.id,
      optionName: option!.name,
      unitExtraPriceMinorUnits: option!.extraPriceMinorUnits,
      quantity: 1,
    });
  }
  return resolved;
}

export async function buildProductLine(
  db: Firestore,
  item: RawProductItem,
  scope: { restaurantId: string },
  channel: string,
  policy: import("./takeawayCatalog").CanonicalChannelPricingPolicy,
  tx?: import("firebase-admin/firestore").Transaction,
  freeUnitCount = 0,
  campaignDiscountMinorUnits = 0,
): Promise<ComputedOrderLine> {
  if (typeof item.productId !== "string" || item.productId.length === 0) {
    invalid("each product item requires a productId.");
  }
  const productId = item.productId;
  const quantity = requireValidQuantity(item.quantity, `product "${productId}"`);

  const product = await loadCanonicalMenuProduct(db, productId, tx);
  if (!product) invalid(`product "${productId}" does not exist.`);
  if (product!.restaurantId !== scope.restaurantId) {
    invalid(`product "${productId}" does not belong to this restaurant.`);
  }
  if (!product!.isAvailable) invalid(`product "${productId}" is not available.`);

  const modifiers = await resolveProductModifiers(product!, item.selectedModifiers);
  // `unitPriceMinorUnits` is already channel-resolved here (includes
  // takeaway's own product-level surcharge, if any) — a catalog reward's
  // `freeUnitCount` therefore automatically covers that surcharge too, with
  // no separate surcharge-specific logic (see `buildOrderLine`'s own P7-C
  // doc comment).
  const unitPriceMinorUnits = resolveProductUnitPriceMinorUnits({
    product: product!,
    channel,
    policy,
  });

  const note = typeof item.note === "string" ? item.note.slice(0, 500) : "";
  return buildOrderLine({
    productId: product!.id,
    productName: product!.name,
    categoryId: product!.categoryId,
    modifiers,
    quantity,
    unitPriceMinorUnits,
    taxBasisPoints: TAKEAWAY_TAX_BASIS_POINTS,
    customerNote: note,
    freeUnitCount,
    campaignDiscountMinorUnits,
  });
}

export async function buildBowlLine(
  db: Firestore,
  item: RawBowlItem,
  scope: { restaurantId: string },
  channel: string,
  policy: import("./takeawayCatalog").CanonicalChannelPricingPolicy,
  tx?: import("firebase-admin/firestore").Transaction,
  freeUnitCount = 0,
  campaignDiscountMinorUnits = 0,
): Promise<ComputedOrderLine> {
  const quantity = requireValidQuantity(item.quantity, "bowl item");
  if (!Array.isArray(item.ingredientIds) || item.ingredientIds.length === 0) {
    invalid("bowl item requires a non-empty ingredientIds array.");
  }

  const modifiers: OrderLineModifierInput[] = [];
  for (const rawId of item.ingredientIds as unknown[]) {
    if (typeof rawId !== "string" || rawId.length === 0) {
      invalid("bowl item: each ingredientId must be a non-empty string.");
    }
    const ingredient = await loadCanonicalBowlIngredient(db, rawId, tx);
    if (!ingredient) invalid(`bowl ingredient "${rawId}" does not exist.`);
    if (ingredient!.restaurantId !== scope.restaurantId) {
      invalid(`bowl ingredient "${rawId}" does not belong to this restaurant.`);
    }
    if (!ingredient!.isAvailable) invalid(`bowl ingredient "${rawId}" is not available.`);
    modifiers.push({
      groupId: ingredient!.categoryId,
      groupName: ingredient!.categoryId,
      optionId: ingredient!.id,
      optionName: ingredient!.name,
      unitExtraPriceMinorUnits: ingredient!.priceMinorUnits,
      quantity: 1,
    });
  }

  // The channel adjustment applies exactly ONCE per bowl unit, added as
  // the line's own unitPrice — ingredient prices live entirely in
  // `modifiers` (mirrors `bowl_builder_screen.dart`'s `_addToCart`: the
  // resolved bowl channel adjustment is `CartItem.price`, the ingredient
  // sum is `selectedModifiers`, never combined into one number). Never
  // per-ingredient: this function calls
  // `resolveBowlUnitAdjustmentMinorUnits` exactly once, outside the
  // ingredient loop above.
  const unitPriceMinorUnits = resolveBowlUnitAdjustmentMinorUnits({ channel, policy });

  const note = typeof item.note === "string" ? item.note.slice(0, 500) : "";
  return buildOrderLine({
    productId: "custom_bowl",
    productName: "Kendi Bowlun",
    categoryId: null,
    modifiers,
    quantity,
    unitPriceMinorUnits,
    taxBasisPoints: TAKEAWAY_TAX_BASIS_POINTS,
    customerNote: note,
    freeUnitCount,
    campaignDiscountMinorUnits,
  });
}

// -----------------------------------------------------------------------
// Idempotency
// -----------------------------------------------------------------------

export function sha256Hex(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

/** Deterministic order id from (actor uid, submissionKey) — a different actor using the same key never collides; the same actor retrying with the same key always maps to the same document. */
function deriveOrderId(uid: string, submissionKey: string): string {
  return `takeaway-${sha256Hex(`${uid}|${submissionKey}`)}`;
}

function deriveOrderNumber(orderId: string): string {
  return `TA-${orderId.slice(orderId.length - 8).toUpperCase()}`;
}

/** A hash of the exact validated/normalized request shape that determines the resulting order — used to distinguish a genuine retry (same key, same effective payload -> reuse) from a key-reuse-with-different-payload attempt (same key, different payload -> fail closed). */
export function computeRequestFingerprint(normalized: unknown): string {
  return sha256Hex(JSON.stringify(normalized));
}

// -----------------------------------------------------------------------
// The callable
// -----------------------------------------------------------------------

export const submitTakeawayOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const uid = request.auth.uid;
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";

    const data = (request.data ?? {}) as Record<string, unknown>;
    const submissionKey = sanitizeSubmissionKey(data.submissionKey);
    const rawItems = parseItems(data.items);
    const contactFirstName = sanitizeContactField(data.contactFirstName, "contactFirstName");
    const contactLastName = sanitizeContactField(data.contactLastName, "contactLastName");
    const contactPhone = sanitizePhone(data.contactPhone);
    const requestedBoncukAmount = sanitizeRequestedBoncukAmount(data.requestedBoncukAmount);
    const selectedRewardId = sanitizeSelectedRewardId(data.selectedRewardId);
    // Server-Authoritative Campaign Engine P8-C (2026-08-25) — the ONLY
    // campaign-related value ever sent by the client. Shape-only validation
    // here; real eligibility is resolved transactionally below.
    const selectedCampaignId = sanitizeSelectedCampaignId(data.selectedCampaignId);

    // Boncuk Loyalty P7-C (2026-08-24) / Campaign Engine P8-C (2026-08-25) —
    // locked rule: cash Boncuk redemption, a catalog reward, and a campaign
    // are mutually exclusive, exactly one benefit per order. A static,
    // data-independent check — applies uniformly to both the guest and
    // authenticated dispatch paths below, before either has a chance to
    // independently reject just one of the fields (which would produce a
    // less specific error for a request that sent more than one). Uses the
    // shared `enforceBenefitExclusivity()` helper (P8-B) rather than a
    // fourth hand-rolled pairwise check.
    enforceBenefitExclusivity({ requestedBoncukAmount, selectedRewardId, selectedCampaignId });

    const hasGuestField = typeof data.takeawaySessionId === "string";
    const hasAuthenticatedFields =
      data.restaurantId !== undefined ||
      data.branchId !== undefined ||
      data.pickupMode !== undefined ||
      data.pickupTime !== undefined;

    const db = getFirestore();

    // ---------------------------------------------------------------
    // Branch dispatch — Faz D.4.1: determined by ENTRY MODE (whether the
    // request references a `takeawayGuestSessions` record), never by
    // `sign_in_provider`. A customer who scans the physical kasadaki Gel
    // Al QR is always a guest/counter order — `channel: takeaway`,
    // `pickupMode: 'asap'`, `customerId: null` — regardless of whether the
    // Firebase Auth identity backing that scan happens to be anonymous or
    // an already-signed-in real, phone-verified customer (Faz D.4's own
    // `TechnicalIdentityProvider.ensureSignedIn()` never overwrites an
    // existing session, by design — see `docs/decisions.md` ADR-027 Faz
    // D.4.1 for the full "entry mode, not auth provider" rationale and
    // the bug this closes: the previous `isRealCustomer`-keyed dispatch
    // rejected exactly this legitimate case with `invalid-argument`).
    //
    // Strict allow-list either way — a request mixing fields from both
    // shapes is rejected outright, never silently ignored.
    // ---------------------------------------------------------------

    if (hasGuestField) {
      if (hasAuthenticatedFields) {
        throw new HttpsError(
          "permission-denied",
          "A QR guest takeaway request must not include restaurantId/branchId/pickupMode/pickupTime.",
        );
      }
      return submitGuestOrder(db, {
        uid,
        submissionKey,
        rawItems,
        contactFirstName,
        contactLastName,
        contactPhone,
        takeawaySessionId: data.takeawaySessionId as string,
        requestedBoncukAmount,
        selectedRewardId,
        selectedCampaignId,
      });
    }

    // No `takeawaySessionId` — the authenticated in-app takeaway path.
    // This path has no session-based authorization mechanism of its own
    // (there is no QR scan to prove the caller's scope/intent), so it
    // still requires a real, phone-verified identity — an anonymous
    // caller can never reach it, whether or not it also spoofs
    // authenticated-branch fields.
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "The authenticated-customer takeaway path requires a phone-verified identity.",
      );
    }
    return submitAuthenticatedOrder(db, {
      uid,
      submissionKey,
      rawItems,
      contactFirstName,
      contactLastName,
      contactPhone,
      restaurantId: data.restaurantId,
      branchId: data.branchId,
      pickupMode: data.pickupMode,
      pickupTime: data.pickupTime,
      requestedBoncukAmount,
      selectedRewardId,
      selectedCampaignId,
    });
  },
);

// -----------------------------------------------------------------------
// QR guest path
// -----------------------------------------------------------------------

async function submitGuestOrder(
  db: Firestore,
  params: {
    uid: string;
    submissionKey: string;
    rawItems: RawItem[];
    contactFirstName: string;
    contactLastName: string;
    contactPhone: string;
    takeawaySessionId: string;
    requestedBoncukAmount: number;
    selectedRewardId: string | null;
    selectedCampaignId: string | null;
  },
) {
  const { uid, submissionKey, rawItems, contactFirstName, contactLastName, contactPhone } =
    params;

  // Boncuk Loyalty P4-B locked rule — guest orders can never redeem Boncuk
  // (no real customer identity to own a loyalty account). Rejected outright,
  // never silently ignored, before the transaction even opens — this is a
  // static request-shape check with no data dependency.
  if (params.requestedBoncukAmount > 0) {
    throw new HttpsError(
      "permission-denied",
      "Guest takeaway orders cannot redeem Boncuk — Boncuk requires a real, phone-verified customer identity.",
    );
  }
  // Boncuk Loyalty P7-C (2026-08-24) — the identical rule extended to
  // catalog rewards: no real customer identity, no loyalty account to debit.
  if (params.selectedRewardId !== null) {
    throw new HttpsError(
      "permission-denied",
      "Guest takeaway orders cannot redeem a catalog reward — this requires a real, phone-verified customer identity.",
    );
  }
  // Server-Authoritative Campaign Engine P8-C (2026-08-25) — the identical
  // rule extended to campaigns: campaign usage reservation requires a
  // durable, real customer identity (both for `perCustomerUsageLimit`
  // tracking and because a guest's own technical uid is not a meaningful
  // "customer" for accounting purposes — mirrors the Boncuk/catalogReward
  // guest exclusion exactly, not a new policy).
  if (params.selectedCampaignId !== null) {
    throw new HttpsError(
      "permission-denied",
      "Guest takeaway orders cannot use a campaign — this requires a real, phone-verified customer identity.",
    );
  }

  const orderId = deriveOrderId(uid, submissionKey);
  const orderNumber = deriveOrderNumber(orderId);

  return db.runTransaction(async (tx) => {
    const sessionRef = db.collection("takeawayGuestSessions").doc(params.takeawaySessionId);
    const sessionDoc = await tx.get(sessionRef);
    if (!sessionDoc.exists) {
      throw new HttpsError("not-found", "Takeaway guest session not found.");
    }
    const session = sessionDoc.data()!;
    if (session.guestAuthUid !== uid) {
      throw new HttpsError("failed-precondition", "This session does not belong to the caller.");
    }
    if (session.status !== "active") {
      throw new HttpsError("failed-precondition", "This session is not active.");
    }
    const sessionExpiresAt =
      typeof session.expiresAt?.toDate === "function" ? session.expiresAt.toDate() : null;
    if (!(sessionExpiresAt instanceof Date) || sessionExpiresAt.getTime() <= Date.now()) {
      throw new HttpsError("failed-precondition", "This session has expired.");
    }

    const restaurantId = String(session.restaurantId);
    const branchId = String(session.branchId);
    const organizationId = String(session.organizationId);

    const policy = await loadCanonicalChannelPricingPolicy(db, restaurantId);
    const { lines, normalizedItems } = await buildLines(db, rawItems, { restaurantId }, policy);
    const pricing = computeOrderPriceBreakdown(lines);

    const normalizedForFingerprint = {
      path: "guest",
      takeawaySessionId: params.takeawaySessionId,
      items: normalizedItems,
      contactFirstName,
      contactLastName,
      contactPhone,
    };
    const fingerprint = computeRequestFingerprint(normalizedForFingerprint);

    const orderRef = db.collection("orders").doc(orderId);
    const existing = await tx.get(orderRef);
    if (existing.exists) {
      const existingData = existing.data()!;
      if (existingData.takeawaySubmissionFingerprint !== fingerprint) {
        throw new HttpsError(
          "failed-precondition",
          "submissionKey was already used with a different order payload.",
        );
      }
      return { orderId, orderNumber: existingData.orderNumber, duplicate: true };
    }

    const now = new Date();
    tx.set(
      orderRef,
      buildOrderDocument({
        organizationId,
        orderId,
        orderNumber,
        channel: "takeaway",
        branchId,
        restaurantId,
        customerId: null,
        guestAuthUid: uid,
        takeawayEntrySessionId: params.takeawaySessionId,
        pickupMode: "asap",
        pickupTime: null,
        contactFirstName,
        contactLastName,
        contactPhone,
        lines,
        pricing,
        now,
        fingerprint,
        selectedBenefitType: "none",
        boncukRedemption: null,
        catalogReward: null,
        campaign: null,
        discountMinorUnits: 0,
      }),
    );

    return { orderId, orderNumber, duplicate: false };
  });
}

// -----------------------------------------------------------------------
// Authenticated customer path
// -----------------------------------------------------------------------

/** The fully-resolved, not-yet-written redemption effects — computed during the transaction's read phase, applied only during its write phase (Firestore requires every `tx.get()` to happen before any `tx.set()`/`tx.create()`). */
interface PendingBoncukRedemption {
  accountRef: FirebaseFirestore.DocumentReference;
  account: LoyaltyAccountData;
  boncukUsed: number;
  ledgerEntryRef: FirebaseFirestore.DocumentReference;
  ledgerEntry: LoyaltyLedgerEntry;
  policy: LoyaltyPolicy;
  policyNeedsProvisioning: boolean;
  orderSnapshot: {
    boncukUsed: number;
    valueMinorUnits: number;
    remainingPayableMinorUnits: number;
    redemptionValueMinorUnitsPerBoncuk: number;
    maxRedemptionBasisPoints: number;
    loyaltyPolicyVersion: number;
  };
}

/** Order-document snapshot shape for a redeemed catalog reward — every field server-resolved, immutable once written (P7-C §7). */
export interface CatalogRewardOrderSnapshot {
  rewardId: string;
  rewardVersion: number;
  title: string;
  boncukCost: number;
  redeemedProductId: string;
  redeemedQuantity: 1;
  coveredValueMinorUnits: number;
  rewardCatalogVersionId: string;
  /**
   * P7-C.1 — the real, server-derived commercial channel this redemption
   * actually happened on (always `"takeaway"` for this callable), snapshot
   * immutably at submission time. A later channel-eligibility change on the
   * live/future reward version can never rewrite an already-placed order's
   * own history — the order always answers "what channel was this
   * REDEEMED on," never "is the current live reward valid for some
   * channel."
   */
  orderChannel: CanonicalCommercialChannel;
}

/** The catalog-reward sibling of [PendingBoncukRedemption] — same "resolved during reads, applied during writes" discipline. */
interface PendingCatalogRewardRedemption {
  accountRef: FirebaseFirestore.DocumentReference;
  account: LoyaltyAccountData;
  boncukCost: number;
  ledgerEntryRef: FirebaseFirestore.DocumentReference;
  ledgerEntry: LoyaltyLedgerEntry;
  orderSnapshot: CatalogRewardOrderSnapshot;
}

async function submitAuthenticatedOrder(
  db: Firestore,
  params: {
    uid: string;
    submissionKey: string;
    rawItems: RawItem[];
    contactFirstName: string;
    contactLastName: string;
    contactPhone: string;
    restaurantId: unknown;
    branchId: unknown;
    pickupMode: unknown;
    pickupTime: unknown;
    requestedBoncukAmount: number;
    selectedRewardId: string | null;
    selectedCampaignId: string | null;
  },
) {
  const { uid, submissionKey, rawItems, contactFirstName, contactLastName, contactPhone } =
    params;

  if (typeof params.restaurantId !== "string" || params.restaurantId.length === 0) {
    invalid("restaurantId is required.");
  }
  if (typeof params.branchId !== "string" || params.branchId.length === 0) {
    invalid("branchId is required.");
  }
  if (params.pickupMode !== "scheduled") {
    invalid('pickupMode must be "scheduled" for an authenticated takeaway order.');
  }
  if (typeof params.pickupTime !== "string") {
    invalid("pickupTime is required.");
  }
  const pickupTime = new Date(params.pickupTime as string);
  if (Number.isNaN(pickupTime.getTime())) {
    invalid("pickupTime is not a valid date.");
  }

  const restaurantId = params.restaurantId as string;
  const branchId = params.branchId as string;

  const orderId = deriveOrderId(uid, submissionKey);
  const orderNumber = deriveOrderNumber(orderId);

  return db.runTransaction(async (tx) => {
    const scope = await resolveActiveTakeawayBranch(db, { restaurantId, branchId });
    if (scope.status === "notFound") {
      throw new HttpsError("not-found", "Branch not found.");
    }
    if (scope.status === "invalid") {
      throw new HttpsError(
        "failed-precondition",
        "Branch is not currently accepting takeaway orders.",
      );
    }

    // Server clock, never the client's — the one place this rule is
    // checked for this new backend path (independent of Faz C's
    // rules-level NOW+20 check, see this phase's own migration-strategy
    // report).
    const minimumPickup = new Date(Date.now() + PICKUP_MINIMUM_LEAD_MINUTES * 60 * 1000);
    if (pickupTime.getTime() < minimumPickup.getTime()) {
      throw new HttpsError(
        "failed-precondition",
        `pickupTime must be at least ${PICKUP_MINIMUM_LEAD_MINUTES} minutes from now.`,
      );
    }

    // -------------------------------------------------------------
    // Boncuk Loyalty P7-C (2026-08-24) — catalog-reward PRE-resolution.
    // Deliberately BEFORE `buildLines`: unlike cash Boncuk redemption
    // (whose validation needs `pricing.grandTotalMinorUnits`, computed only
    // AFTER lines are built), a catalog reward's validity/eligibility/
    // balance checks need no pricing at all — only the reward definition
    // and the raw cart contents. Resolving it here lets `buildLines` below
    // receive `rewardedProductId` and apply the free unit as it builds the
    // line, rather than requiring a second pricing pass or a post-hoc
    // grandTotal adjustment. Every `tx.get()` here still happens safely
    // before this transaction's first write.
    // -------------------------------------------------------------
    const organizationId = scope.organizationId!;
    let catalogRewardPreCheck: { reward: LoyaltyRewardCatalogEntry; redeemedProductId: string } | null =
      null;
    if (params.selectedRewardId !== null) {
      const reward = await loadLoyaltyRewardForRedemption(db, params.selectedRewardId, tx);
      if (!reward || reward.organizationId !== organizationId) {
        boncukError("invalid-argument", "The selected reward does not exist.", "catalogReward/reward-not-found");
      }
      if (!isRewardCurrentlyValid(reward, Timestamp.now())) {
        boncukError(
          "failed-precondition",
          "The selected reward is not currently active/valid.",
          "catalogReward/reward-not-currently-valid",
        );
      }
      // Boncuk Loyalty P7-C.1 (2026-08-24) — the real, server-derived
      // channel of THIS order is always the literal "takeaway" for this
      // callable (never read from client input — there is structurally no
      // field a client could use to claim a different channel). Fails
      // closed BEFORE any pricing/build work if the reward's own
      // eligibleChannels doesn't include it: no debit, no ledger entry, no
      // order created with the reward applied.
      if (!reward.eligibleChannels.includes(TAKEAWAY_COMMERCIAL_CHANNEL)) {
        boncukError(
          "failed-precondition",
          "The selected reward is not available for the Gel Al (Takeaway) channel.",
          "catalogReward/channel-not-eligible",
        );
      }
      const redeemedProductId = findFirstEligibleCartProductId(rawItems, reward.eligibleProductIds);
      if (!redeemedProductId) {
        boncukError(
          "invalid-argument",
          "None of the items in this order are eligible for the selected reward.",
          "catalogReward/product-not-in-cart",
        );
      }
      catalogRewardPreCheck = { reward, redeemedProductId };
    }

    // -------------------------------------------------------------
    // Server-Authoritative Campaign Engine P8-C (2026-08-25) — campaign
    // PRE-resolution (existence/tenant/active/archived/channel/schedule).
    // Deliberately BEFORE `buildLines`: these checks need no pricing at
    // all. Minimum-basket/targeting/rule-satisfaction checks DO need
    // priced lines — resolved just below, after `buildLines`'s first pass.
    // Mutually exclusive with catalogReward (enforced pre-transaction by
    // `enforceBenefitExclusivity`), so at most one of
    // `catalogRewardPreCheck`/`campaignPreCheck` is ever non-null.
    // -------------------------------------------------------------
    let campaignPreCheck: CampaignDefinition | null = null;
    if (params.selectedCampaignId !== null) {
      const campaignSnap = await tx.get(db.collection(CAMPAIGNS_COLLECTION).doc(params.selectedCampaignId));
      const campaign = parseCampaignDefinition(campaignSnap.exists ? campaignSnap.data() : undefined);
      if (!campaign || campaign.organizationId !== organizationId) {
        boncukError("invalid-argument", "The selected campaign does not exist.", "campaign/not-found");
      }
      if (!campaign.active) {
        boncukError(
          "failed-precondition",
          "The selected campaign is not currently active.",
          "campaign/inactive",
        );
      }
      if (campaign.archived) {
        boncukError(
          "failed-precondition",
          "The selected campaign has been archived.",
          "campaign/archived",
        );
      }
      if (!campaign.eligibleChannels.includes(TAKEAWAY_COMMERCIAL_CHANNEL)) {
        boncukError(
          "failed-precondition",
          "The selected campaign is not available for the Gel Al (Takeaway) channel.",
          "campaign/channel-not-eligible",
        );
      }

      // Trusted branch timezone — never the client's clock, never a
      // hardcoded default when the branch has its own real value. Falls
      // back to the same single-tenant default `getCustomerActiveCampaigns
      // .ts` uses only when the branch document is missing a `timezone`
      // field (should not happen for a real branch, but never crashes).
      const branchSnap = await tx.get(db.collection("branches").doc(branchId));
      const branchTimeZone =
        branchSnap.exists && typeof branchSnap.data()!.timezone === "string"
          ? (branchSnap.data()!.timezone as string)
          : DEFAULT_ORGANIZATION_TIMEZONE;

      if (!isCampaignScheduleCurrentlyOpen(campaign.schedule, Timestamp.now(), branchTimeZone)) {
        boncukError(
          "failed-precondition",
          "The selected campaign is not currently within its scheduled window.",
          "campaign/schedule-not-open",
        );
      }

      campaignPreCheck = campaign;
    }

    const pricingPolicy = await loadCanonicalChannelPricingPolicy(db, restaurantId);
    const pass1 = await buildLines(
      db,
      rawItems,
      { restaurantId },
      pricingPolicy,
      catalogRewardPreCheck?.redeemedProductId ?? null,
    );

    let lines = pass1.lines;
    const rewardAppliedLineIndex = pass1.rewardAppliedLineIndex;
    let selectedBenefitType: SelectedBenefitType = "none";
    let campaignDiscountMinorUnits = 0;
    let campaignOrderSnapshot: CampaignOrderSnapshot | null = null;

    // -------------------------------------------------------------
    // Server-Authoritative Campaign Engine P8-C (2026-08-25) — campaign
    // discount resolution against REAL, channel-priced lines (this is why
    // a campaign needs a first `buildLines` pass — unlike catalogReward's
    // `freeUnitCount`, a percentage/fixed-amount/product/category discount
    // cannot be determined before real unit prices are known). Minimum
    // basket is evaluated against the PRE-CAMPAIGN basket (§ locked rule)
    // — `resolveCampaignDiscount` computes that internally from `pass1`'s
    // own un-discounted lines, never from a client-supplied amount.
    // -------------------------------------------------------------
    if (campaignPreCheck !== null) {
      const campaign = campaignPreCheck;
      const discountResult = resolveCampaignDiscount(campaign, pass1.campaignLines);
      if (discountResult.status === "minimum-basket-not-met") {
        boncukError(
          "failed-precondition",
          "This order does not meet the selected campaign's minimum basket requirement.",
          "campaign/minimum-basket-not-met",
        );
      }
      if (discountResult.status === "trigger-quantity-not-met") {
        boncukError(
          "failed-precondition",
          "This order does not meet the selected campaign's required purchase quantity.",
          "campaign/trigger-quantity-not-met",
        );
      }
      if (discountResult.status === "no-eligible-line") {
        boncukError(
          "invalid-argument",
          "None of the items in this order are eligible for the selected campaign.",
          "campaign/no-eligible-line",
        );
      }

      // discountResult.status === "applied" from here on.
      const lineDiscounts = new Map(
        discountResult.lineDiscounts.map((d) => [d.lineIndex, d.discountMinorUnits]),
      );
      // PASS 2 — rebuild lines with the resolved per-line campaign discount
      // applied. `rewardedProductId: null` — campaign and catalogReward are
      // mutually exclusive, so this pass never needs `freeUnitCount` too.
      const pass2 = await buildLines(db, rawItems, { restaurantId }, pricingPolicy, null, lineDiscounts);
      lines = pass2.lines;

      selectedBenefitType = "campaign";
      campaignDiscountMinorUnits = discountResult.totalDiscountMinorUnits;
      campaignOrderSnapshot = {
        campaignId: campaign.campaignId,
        campaignVersion: campaign.version,
        title: campaign.title,
        campaignType: campaign.campaignType,
        appliedRule: campaign.rule,
        appliedValue: discountResult.appliedValue,
        discountMinorUnits: discountResult.totalDiscountMinorUnits,
        orderChannel: TAKEAWAY_COMMERCIAL_CHANNEL,
      };
    }

    // Never patch grandTotal afterward — `pricing` is derived exactly once,
    // from whichever `lines` (pass1, or pass2 if a campaign discount was
    // applied) are final at this point.
    const pricing = computeOrderPriceBreakdown(lines);

    const normalizedForFingerprint = {
      path: "authenticated",
      restaurantId,
      branchId,
      pickupMode: "scheduled",
      pickupTime: pickupTime.toISOString(),
      items: pass1.normalizedItems,
      contactFirstName,
      contactLastName,
      contactPhone,
      // Boncuk Loyalty P4-B §10 — a retry that reuses the same submissionKey
      // but changes requestedBoncukAmount must be treated as "a different
      // order payload," not silently accepted or silently ignored. Folding
      // this into the fingerprint makes the EXISTING mismatch-rejection
      // branch below (`takeawaySubmissionFingerprint !== fingerprint`)
      // cover it for free, with no separate special-case check.
      requestedBoncukAmount: params.requestedBoncukAmount,
      // Boncuk Loyalty P7-C — same reasoning, for the mutually exclusive
      // catalog-reward selection.
      selectedRewardId: params.selectedRewardId,
      // Server-Authoritative Campaign Engine P8-C — same reasoning, for the
      // mutually exclusive campaign selection.
      selectedCampaignId: params.selectedCampaignId,
    };
    const fingerprint = computeRequestFingerprint(normalizedForFingerprint);

    const orderRef = db.collection("orders").doc(orderId);
    const existing = await tx.get(orderRef);
    if (existing.exists) {
      const existingData = existing.data()!;
      if (existingData.takeawaySubmissionFingerprint !== fingerprint) {
        throw new HttpsError(
          "failed-precondition",
          "submissionKey was already used with a different order payload.",
        );
      }
      return { orderId, orderNumber: existingData.orderNumber, duplicate: true };
    }

    // -------------------------------------------------------------
    // Boncuk Loyalty P4-B §7 — redemption resolution (reads only; this
    // whole block runs strictly before the transaction's first write
    // below, so every tx.get() here is safely ordered ahead of every
    // tx.set()/tx.create() in this transaction, including the dedupe
    // read above).
    //
    // §7 step 5 ("if Boncuk requested: require a real phone customer") is
    // already structurally guaranteed here — submitAuthenticatedOrder is
    // only ever reached after the top-level handler's own isRealCustomer
    // check rejects every anonymous/guest caller before dispatch. No
    // additional branch is needed; this comment documents the existing
    // invariant this code relies on.
    // -------------------------------------------------------------
    let pendingRedemption: PendingBoncukRedemption | null = null;
    let pendingCatalogReward: PendingCatalogRewardRedemption | null = null;

    if (params.requestedBoncukAmount > 0) {
      // §2 — cap basis is grandTotal MINUS tip, never grossSubtotal. Tip is
      // always 0 for takeaway today (buildOrderDocument always stamps
      // `tip: moneyField(0)`) — no persisted tip field exists yet to read.
      const TAKEAWAY_TIP_MINOR_UNITS = 0;
      const boncukEligibleOrderAmountMinorUnits =
        pricing.grandTotalMinorUnits - TAKEAWAY_TIP_MINOR_UNITS;
      if (boncukEligibleOrderAmountMinorUnits < 0) {
        boncukError(
          "internal",
          "Computed a negative Boncuk-eligible order amount.",
          "boncuk/redemption-not-allowed",
        );
      }

      const accountRef = db
        .collection(LOYALTY_ACCOUNTS_COLLECTION)
        .doc(`${organizationId}_${uid}`);
      const loyaltyPolicyRef = loyaltyPolicyDocRef(db, organizationId);
      const loyaltyPolicyBootstrapDocRef = loyaltyPolicyBootstrapRef(db, organizationId);

      const accountSnap = await tx.get(accountRef);
      const loyaltyPolicySnap = await tx.get(loyaltyPolicyRef);
      const loyaltyPolicyBootstrapSnap = await tx.get(loyaltyPolicyBootstrapDocRef);

      const nowForPolicy = Timestamp.now();
      const policyResult = readLoyaltyPolicyInTransaction(
        loyaltyPolicySnap,
        loyaltyPolicyBootstrapSnap,
        organizationId,
        nowForPolicy,
      );
      if (
        policyResult.status === "corrupt-policy-state" ||
        policyResult.status === "missing-live-policy"
      ) {
        boncukError(
          "failed-precondition",
          "Loyalty economics are temporarily unavailable for this organization.",
          "boncuk/policy-unavailable",
        );
      }
      const loyaltyPolicy = policyResult.policy;

      const accountResult = resolveAccountForRedemption(accountSnap);
      if (accountResult.status === "missing-loyalty-account") {
        boncukError(
          "failed-precondition",
          "No loyalty account exists for this customer — cannot redeem Boncuk.",
          "boncuk/account-unavailable",
        );
      }
      if (accountResult.status === "inconsistent-loyalty-account-state") {
        boncukError(
          "failed-precondition",
          "This customer's loyalty account is in an inconsistent state.",
          "boncuk/account-unavailable",
        );
      }
      const account = accountResult.account;

      const calc = calculateBoncukRedemption({
        requestedBoncukAmount: params.requestedBoncukAmount,
        spendableBalance: account.spendableBalance,
        grandTotalMinorUnits: pricing.grandTotalMinorUnits,
        boncukEligibleOrderAmountMinorUnits,
        redemptionValueMinorUnitsPerBoncuk: loyaltyPolicy.redemptionValueMinorUnitsPerBoncuk,
        maxRedemptionBasisPoints: loyaltyPolicy.maxRedemptionBasisPoints,
      });
      if (calc.status === "exceeds-max-usable") {
        boncukError(
          "invalid-argument",
          `requestedBoncukAmount exceeds the maximum usable Boncuk for this order (max ${calc.maxUsableBoncuk}).`,
          "boncuk/exceeds-max-usable",
        );
      }

      const ledgerEntryId = deriveLoyaltyLedgerEntryId({
        organizationId,
        customerId: uid,
        entryType: "boncukRedemption",
        sourceId: orderId,
      });
      const ledgerEntryRef = db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(ledgerEntryId);
      const ledgerSnap = await tx.get(ledgerEntryRef);
      if (ledgerSnap.exists) {
        // Defense-in-depth only — the order-level dedupe check above
        // already guarantees this transaction only reaches here for a
        // genuinely new order, so this should never happen. Fail closed
        // rather than silently proceeding.
        boncukError(
          "failed-precondition",
          "A Boncuk redemption ledger entry already exists for this order.",
          "boncuk/redemption-not-allowed",
        );
      }

      selectedBenefitType = "boncukRedemption";
      pendingRedemption = {
        accountRef,
        account,
        boncukUsed: calc.boncukUsed,
        ledgerEntryRef,
        ledgerEntry: {
          organizationId,
          customerId: uid,
          entryType: "boncukRedemption",
          entitlementDeltaBoncuk: 0,
          spendableDeltaBoncuk: 0 - calc.boncukUsed,
          debtDeltaBoncuk: 0,
          sourceId: orderId,
          orderId,
          amountBasisMinorUnits: calc.valueMinorUnits,
          earningCarryNumeratorBefore: null,
          earningCarryDenominatorBefore: null,
          earningCarryNumeratorAfter: null,
          earningCarryDenominatorAfter: null,
          earningSpendMinorUnits: null,
          earningBoncukAmount: null,
          loyaltyPolicyVersion: loyaltyPolicy.version,
          debtBeforeBoncuk: account.boncukDebt,
          debtAfterBoncuk: account.boncukDebt,
          redemptionValueMinorUnitsPerBoncuk: loyaltyPolicy.redemptionValueMinorUnitsPerBoncuk,
          maxRedemptionBasisPoints: loyaltyPolicy.maxRedemptionBasisPoints,
          idempotencyKey: orderId,
          reversalOf: null,
          expiresAt: null,
          metadata: null,
        } as LoyaltyLedgerEntry,
        policy: loyaltyPolicy,
        policyNeedsProvisioning: policyResult.needsProvisioning,
        orderSnapshot: {
          boncukUsed: calc.boncukUsed,
          valueMinorUnits: calc.valueMinorUnits,
          remainingPayableMinorUnits: calc.remainingPayableMinorUnits,
          redemptionValueMinorUnitsPerBoncuk: loyaltyPolicy.redemptionValueMinorUnitsPerBoncuk,
          maxRedemptionBasisPoints: loyaltyPolicy.maxRedemptionBasisPoints,
          loyaltyPolicyVersion: loyaltyPolicy.version,
        },
      };
    } else if (catalogRewardPreCheck !== null) {
      // -------------------------------------------------------------
      // Boncuk Loyalty P7-C — catalog-reward FINAL resolution. Reads only,
      // still strictly before this transaction's first write. Deliberately
      // does NOT touch `loyaltyPolicies` at all — a catalog reward's cost
      // is a fixed property of the reward itself, entirely independent of
      // the organization's cash earning/redemption rate.
      // -------------------------------------------------------------
      const { reward, redeemedProductId } = catalogRewardPreCheck;
      if (rewardAppliedLineIndex === null) {
        // Structurally unreachable — buildLines was given the exact same
        // redeemedProductId findFirstEligibleCartProductId just found, so
        // it always applies the free unit to a real line. Defensive only.
        boncukError(
          "internal",
          "Failed to apply the catalog reward to a cart line.",
          "catalogReward/product-not-in-cart",
        );
      }
      const rewardedLine = lines[rewardAppliedLineIndex];
      const coveredValueMinorUnits = rewardedLine.lineDiscountMinorUnits;

      const accountRef = db.collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`);
      const accountSnap = await tx.get(accountRef);
      const accountResult = resolveAccountForRedemption(accountSnap);
      if (accountResult.status === "missing-loyalty-account") {
        boncukError(
          "failed-precondition",
          "No loyalty account exists for this customer — cannot redeem a catalog reward.",
          "catalogReward/account-unavailable",
        );
      }
      if (accountResult.status === "inconsistent-loyalty-account-state") {
        boncukError(
          "failed-precondition",
          "This customer's loyalty account is in an inconsistent state.",
          "catalogReward/account-unavailable",
        );
      }
      const account = accountResult.account;

      const resolution = resolveCatalogRewardRedemption({
        reward,
        now: new Date(),
        organizationId,
        orderChannel: TAKEAWAY_COMMERCIAL_CHANNEL,
        requestedProductId: redeemedProductId,
        spendableBalance: account.spendableBalance,
      });
      if (resolution.status === "insufficient-balance") {
        boncukError(
          "failed-precondition",
          `Insufficient Boncuk balance for this reward (requires ${resolution.requiredBoncuk}, has ${resolution.availableBoncuk}).`,
          "catalogReward/insufficient-balance",
        );
      }
      if (resolution.status !== "ok") {
        // reward-not-found / organization-mismatch / reward-not-currently-valid
        // / product-not-eligible — all already independently checked above
        // (same reward object, same product, same clock reference), so this
        // is defense-in-depth against a logic drift between the two checks,
        // never expected to actually trigger.
        boncukError(
          "failed-precondition",
          "The selected reward can no longer be redeemed.",
          "catalogReward/reward-not-currently-valid",
        );
      }
      const { snapshot } = resolution;

      const ledgerEntryId = deriveLoyaltyLedgerEntryId({
        organizationId,
        customerId: uid,
        entryType: "catalogRedemption",
        sourceId: orderId,
      });
      const ledgerEntryRef = db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(ledgerEntryId);
      const ledgerSnap = await tx.get(ledgerEntryRef);
      if (ledgerSnap.exists) {
        // Defense-in-depth only, mirrors the boncukRedemption branch above
        // — the order-level dedupe check already guarantees this
        // transaction only reaches here for a genuinely new order.
        boncukError(
          "failed-precondition",
          "A catalog reward redemption ledger entry already exists for this order.",
          "catalogReward/reward-not-currently-valid",
        );
      }

      selectedBenefitType = "catalogReward";
      pendingCatalogReward = {
        accountRef,
        account,
        boncukCost: snapshot.boncukCost,
        ledgerEntryRef,
        ledgerEntry: {
          organizationId,
          customerId: uid,
          entryType: "catalogRedemption",
          entitlementDeltaBoncuk: 0,
          spendableDeltaBoncuk: 0 - snapshot.boncukCost,
          debtDeltaBoncuk: 0,
          sourceId: orderId,
          orderId,
          amountBasisMinorUnits: coveredValueMinorUnits,
          earningCarryNumeratorBefore: null,
          earningCarryDenominatorBefore: null,
          earningCarryNumeratorAfter: null,
          earningCarryDenominatorAfter: null,
          earningSpendMinorUnits: null,
          earningBoncukAmount: null,
          loyaltyPolicyVersion: null,
          debtBeforeBoncuk: account.boncukDebt,
          debtAfterBoncuk: account.boncukDebt,
          redemptionValueMinorUnitsPerBoncuk: null,
          maxRedemptionBasisPoints: null,
          idempotencyKey: orderId,
          reversalOf: null,
          expiresAt: null,
          metadata: { entryType: "catalogRedemption", rewardId: snapshot.rewardId },
        } as LoyaltyLedgerEntry,
        orderSnapshot: {
          rewardId: snapshot.rewardId,
          rewardVersion: snapshot.rewardVersion,
          title: snapshot.title,
          boncukCost: snapshot.boncukCost,
          redeemedProductId: snapshot.redeemedProductId,
          redeemedQuantity: 1,
          coveredValueMinorUnits,
          rewardCatalogVersionId: loyaltyRewardCatalogVersionDocId(
            snapshot.rewardId,
            snapshot.rewardVersion,
          ),
          orderChannel: TAKEAWAY_COMMERCIAL_CHANNEL,
        },
      };
    }

    // -------------------------------------------------------------
    // Write phase — every tx.get() THIS TRANSACTION has performed so far
    // happened above. `reserveCampaignUsage` below still performs its OWN
    // reads (usage counters, reservation existence) before its own writes
    // — called here, as the very first statement of this phase, so those
    // reads are still safely ordered ahead of every tx.set()/tx.create()
    // in the entire transaction, including its own and the order-creation
    // write below (Server-Authoritative Campaign Engine P8-C, 2026-08-25).
    // -------------------------------------------------------------
    const now = new Date();

    if (campaignPreCheck !== null) {
      const reserveResult = await reserveCampaignUsage(db, tx, {
        organizationId,
        campaignId: campaignPreCheck.campaignId,
        // Always a real, phone-verified customer here — campaign selection
        // is rejected for guest takeaway orders before this function is
        // ever reached (see `submitGuestOrder`'s own rejection above).
        customerId: uid,
        orderId,
        usageLimit: campaignPreCheck.usageLimit,
        perCustomerUsageLimit: campaignPreCheck.perCustomerUsageLimit,
      });
      if (reserveResult.status === "global-limit-reached") {
        boncukError(
          "failed-precondition",
          "The selected campaign has reached its usage limit.",
          "campaign/usage-limit-reached",
        );
      }
      if (reserveResult.status === "customer-limit-reached") {
        boncukError(
          "failed-precondition",
          "You have already used the selected campaign the maximum number of times.",
          "campaign/customer-usage-limit-reached",
        );
      }
      if (reserveResult.status === "already-reserved") {
        // Defense-in-depth only, mirrors the existing ledger-entry-exists
        // checks elsewhere in this file — the order-level dedupe check
        // above already guarantees this transaction only reaches here for
        // a genuinely new order, so a reservation for this exact orderId
        // should never already exist. Fail closed rather than silently
        // proceeding.
        boncukError(
          "failed-precondition",
          "A campaign usage reservation already exists for this order.",
          "campaign/reservation-conflict",
        );
      }
    }

    if (pendingRedemption) {
      if (pendingRedemption.policyNeedsProvisioning) {
        writeDefaultLoyaltyPolicyInTransaction(tx, db, pendingRedemption.policy);
      }
      tx.set(pendingRedemption.accountRef, {
        ...pendingRedemption.account,
        spendableBalance: pendingRedemption.account.spendableBalance - pendingRedemption.boncukUsed,
        lifetimeRedeemed: pendingRedemption.account.lifetimeRedeemed + pendingRedemption.boncukUsed,
        revision: pendingRedemption.account.revision + 1,
        updatedAt: Timestamp.fromDate(now),
      });
      tx.create(pendingRedemption.ledgerEntryRef, {
        ...pendingRedemption.ledgerEntry,
        createdAt: Timestamp.fromDate(now),
      });
    }

    if (pendingCatalogReward) {
      tx.set(pendingCatalogReward.accountRef, {
        ...pendingCatalogReward.account,
        spendableBalance: pendingCatalogReward.account.spendableBalance - pendingCatalogReward.boncukCost,
        lifetimeRedeemed: pendingCatalogReward.account.lifetimeRedeemed + pendingCatalogReward.boncukCost,
        revision: pendingCatalogReward.account.revision + 1,
        updatedAt: Timestamp.fromDate(now),
      });
      tx.create(pendingCatalogReward.ledgerEntryRef, {
        ...pendingCatalogReward.ledgerEntry,
        createdAt: Timestamp.fromDate(now),
      });
    }

    tx.set(
      orderRef,
      buildOrderDocument({
        organizationId: scope.organizationId!,
        orderId,
        orderNumber,
        channel: "takeaway",
        branchId,
        restaurantId,
        customerId: uid,
        guestAuthUid: null,
        takeawayEntrySessionId: null,
        pickupMode: "scheduled",
        pickupTime,
        contactFirstName,
        contactLastName,
        contactPhone,
        lines,
        pricing,
        now,
        fingerprint,
        selectedBenefitType,
        boncukRedemption: pendingRedemption ? pendingRedemption.orderSnapshot : null,
        catalogReward: pendingCatalogReward ? pendingCatalogReward.orderSnapshot : null,
        campaign: campaignOrderSnapshot,
        discountMinorUnits: campaignDiscountMinorUnits,
      }),
    );

    return { orderId, orderNumber, duplicate: false };
  });
}

// -----------------------------------------------------------------------
// Shared line-building + order document assembly
// -----------------------------------------------------------------------

/**
 * Boncuk Loyalty P7-C (2026-08-24) — finds the FIRST `kind: "product"` cart
 * item whose `productId` is one of the reward's explicit
 * `eligibleProductIds`, in cart order. A deterministic, documented tie-
 * break for the (expected-rare) case of the same eligible product
 * appearing as more than one separate cart line (different modifier
 * selections) — only ONE line, the first, is ever considered for the
 * reward, matching "only ONE product unit is redeemed per catalog
 * reward." `kind: "bowl"` (Bowl Builder custom bowls) items can never
 * match — they have no real canonical `productId` at all, structurally
 * ineligible by construction, not by a special-cased check here.
 */
export function findFirstEligibleCartProductId(
  rawItems: RawItem[],
  eligibleProductIds: readonly string[],
): string | null {
  for (const item of rawItems) {
    if (item.kind === "product" && typeof item.productId === "string") {
      if (eligibleProductIds.includes(item.productId)) return item.productId;
    }
  }
  return null;
}

/**
 * Server-Authoritative Campaign Engine P8-C (2026-08-25) —
 * `campaignLineDiscounts` (line index -> resolved minor-unit discount) is
 * threaded through to each line's own `buildOrderLine` call, and every
 * built line's real, channel-priced info is ALSO captured into
 * `campaignLines` (a `CampaignPriceableLine[]`, `campaignPricing.ts`'s own
 * input shape) — piggybacking on data already fetched for the line, no
 * extra Firestore reads. `campaignLineDiscounts: null` (the default) means
 * "no campaign discount to apply this call" — every pre-P8-C caller
 * behaves identically to before. A bowl line's own `productId`/`categoryId`
 * are always `null` in `campaignLines` — it has no real canonical product
 * id, so it can never match a product/category-scoped campaign rule (the
 * same structural limitation `catalogReward` already has).
 */
async function buildLines(
  db: Firestore,
  rawItems: RawItem[],
  scope: { restaurantId: string },
  policy: import("./takeawayCatalog").CanonicalChannelPricingPolicy,
  rewardedProductId: string | null = null,
  campaignLineDiscounts: Map<number, number> | null = null,
): Promise<{
  lines: ComputedOrderLine[];
  normalizedItems: unknown[];
  rewardAppliedLineIndex: number | null;
  campaignLines: CampaignPriceableLine[];
}> {
  const lines: ComputedOrderLine[] = [];
  const normalizedItems: unknown[] = [];
  const campaignLines: CampaignPriceableLine[] = [];
  let rewardAppliedLineIndex: number | null = null;
  for (const item of rawItems) {
    const lineIndex = lines.length;
    const campaignDiscountForLine = campaignLineDiscounts?.get(lineIndex) ?? 0;
    if (item.kind === "product") {
      // Only the FIRST matching line ever receives the free unit — mirrors
      // findFirstEligibleCartProductId's own tie-break exactly, so the
      // pre-buildLines eligibility scan and this application are always
      // consistent with each other.
      const isRewardedLine =
        rewardAppliedLineIndex === null &&
        rewardedProductId !== null &&
        item.productId === rewardedProductId;
      const line = await buildProductLine(
        db,
        item,
        scope,
        "takeaway",
        policy,
        undefined,
        isRewardedLine ? 1 : 0,
        campaignDiscountForLine,
      );
      if (isRewardedLine) rewardAppliedLineIndex = lineIndex;
      lines.push(line);
      campaignLines.push({
        lineIndex,
        productId: line.productId,
        categoryId: line.categoryId,
        quantity: line.quantity,
        unitBaseMinorUnits: line.unitPriceMinorUnits + line.modifierTotalMinorUnits,
      });
      normalizedItems.push({
        kind: "product",
        productId: item.productId,
        quantity: item.quantity,
        selectedModifiers: item.selectedModifiers ?? [],
        note: item.note ?? "",
      });
    } else {
      const line = await buildBowlLine(
        db,
        item,
        scope,
        "takeaway",
        policy,
        undefined,
        0,
        campaignDiscountForLine,
      );
      lines.push(line);
      campaignLines.push({
        lineIndex,
        // A Bowl Builder line has no real canonical product/category id —
        // structurally ineligible for any product/category-scoped campaign,
        // never a fake id standing in for one.
        productId: null,
        categoryId: null,
        quantity: line.quantity,
        unitBaseMinorUnits: line.unitPriceMinorUnits + line.modifierTotalMinorUnits,
      });
      normalizedItems.push({
        kind: "bowl",
        quantity: item.quantity,
        ingredientIds: item.ingredientIds,
        note: item.note ?? "",
      });
    }
  }
  return { lines, normalizedItems, rewardAppliedLineIndex, campaignLines };
}

function buildOrderDocument(params: {
  organizationId: string;
  orderId: string;
  orderNumber: string;
  channel: "takeaway";
  branchId: string;
  restaurantId: string;
  customerId: string | null;
  guestAuthUid: string | null;
  takeawayEntrySessionId: string | null;
  pickupMode: "asap" | "scheduled";
  pickupTime: Date | null;
  contactFirstName: string;
  contactLastName: string;
  contactPhone: string;
  lines: ComputedOrderLine[];
  pricing: import("./takeawayPricing").ComputedPriceBreakdown;
  now: Date;
  fingerprint: string;
  selectedBenefitType: SelectedBenefitType;
  boncukRedemption: {
    boncukUsed: number;
    valueMinorUnits: number;
    remainingPayableMinorUnits: number;
    redemptionValueMinorUnitsPerBoncuk: number;
    maxRedemptionBasisPoints: number;
    loyaltyPolicyVersion: number;
  } | null;
  catalogReward: CatalogRewardOrderSnapshot | null;
  /**
   * Server-Authoritative Campaign Engine P8-C (2026-08-25) — the immutable
   * per-order campaign snapshot when `selectedBenefitType === "campaign"`;
   * `null` otherwise, including every pre-P8-C order. Never re-read from
   * the live `campaigns` document by any future consumer — this snapshot
   * is the sole source of historical truth for what was applied.
   */
  campaign: CampaignOrderSnapshot | null;
  /**
   * The EXACT total campaign discount already baked into `pricing`'s own
   * `grossSubtotal`/`grandTotal` via the discounted lines above — `0` for
   * every order without a campaign (preserves `pricing.discount:
   * moneyField(0)`'s exact pre-P8-C behavior for the no-campaign/
   * boncukRedemption/catalogReward cases). Locked requirement:
   * `pricing.discount` must equal the exact campaign discount applied,
   * never a separately-computed or approximated figure.
   */
  discountMinorUnits: number;
}) {
  const currencyCode = "TRY";
  const moneyField = (minorUnits: number) => ({ minorUnits, currencyCode });

  return {
    organizationId: params.organizationId,
    orderId: params.orderId,
    orderNumber: params.orderNumber,
    status: "pendingConfirmation",
    channel: params.channel,
    // Boncuk Loyalty P2A security fix (2026-08-21) — server-stamped only,
    // never accepted from a request parameter. See
    // `functions/src/orderPricingAuthority.ts` for why this is a distinct
    // concept from `channel`.
    pricingAuthority: ORDER_PRICING_AUTHORITY_SERVER_V1,
    branchId: params.branchId,
    restaurantId: params.restaurantId,
    customerId: params.customerId,
    tableId: null,
    tableSessionId: null,
    guestSessionId: null,
    guestAuthUid: params.guestAuthUid,
    takeawayEntrySessionId: params.takeawayEntrySessionId,
    pickupMode: params.pickupMode,
    pickupTime: params.pickupTime ? params.pickupTime.toISOString() : null,
    pickupTimeTimestamp: params.pickupTime,
    contactFirstName: params.contactFirstName,
    contactLastName: params.contactLastName,
    contactPhone: params.contactPhone,
    courierVisibility: "hidden",
    lines: params.lines.map((line) => ({
      productId: line.productId,
      productName: line.productName,
      modifiers: line.modifiers.map((m) => ({
        groupId: m.groupId,
        groupName: m.groupName,
        optionId: m.optionId,
        optionName: m.optionName,
        unitExtraPrice: moneyField(m.unitExtraPriceMinorUnits),
        quantity: m.quantity,
      })),
      quantity: line.quantity,
      unitPrice: moneyField(line.unitPriceMinorUnits),
      lineDiscount: moneyField(line.lineDiscountMinorUnits),
      taxRateBasisPoints: line.taxBasisPoints,
      kitchenNote: line.kitchenNote,
      customerNote: line.customerNote,
    })),
    pricing: {
      grossSubtotal: moneyField(params.pricing.grossSubtotalMinorUnits),
      discount: moneyField(params.discountMinorUnits),
      taxableBase: moneyField(params.pricing.taxableBaseMinorUnits),
      vatAmount: moneyField(params.pricing.vatAmountMinorUnits),
      serviceFee: moneyField(0),
      deliveryFee: moneyField(0),
      packagingFee: moneyField(0),
      tip: moneyField(0),
      grandTotal: moneyField(params.pricing.grandTotalMinorUnits),
    },
    // Boncuk Loyalty P4-B — settlement, not discount (P4-A, accepted): the
    // `pricing` block above is never touched by cash Boncuk redemption.
    // This is a parallel snapshot of how part of that unchanged total is
    // being paid — server-computed and server-stamped only, never accepted
    // from the request (see `firestore.rules`'
    // `clientOrderCreateOmitsBoncukRedemption()` for why a direct-client
    // create can never forge either field).
    //
    // Boncuk Loyalty P7-C (2026-08-24) — a catalog reward is DIFFERENT: it
    // genuinely changes `pricing` above (the rewarded line's own
    // `lineDiscount`, and therefore `grossSubtotal`/`grandTotal`, already
    // reflect it — see `takeawayPricing.ts`'s `buildOrderLine` doc
    // comment). `catalogReward` here is a read-only AUDIT snapshot of what
    // was redeemed and why the total is what it is, never a second,
    // independently-applied discount — the price change happened once,
    // during line-building, not twice.
    selectedBenefitType: params.selectedBenefitType,
    boncukRedemption: params.boncukRedemption,
    catalogReward: params.catalogReward,
    // Server-Authoritative Campaign Engine P8-C (2026-08-24) — genuinely
    // changes `pricing` above (like `catalogReward`, unlike
    // `boncukRedemption`'s settlement-not-discount model) via the
    // already-discounted lines; this is a read-only AUDIT snapshot of what
    // was applied, never re-derived or re-applied from this field.
    campaign: params.campaign,
    statusHistory: [
      {
        id: `${params.orderId}-transition-1`,
        type: "statusChange",
        description: "Status changed from created to pendingConfirmation",
        actor: "customer",
        timestamp: params.now.toISOString(),
        previousValue: "created",
        newValue: "pendingConfirmation",
      },
    ],
    version: 1,
    timestamps: {
      created: params.now.toISOString(),
      confirmed: null,
      preparing: null,
      ready: null,
      served: null,
      completed: null,
      cancelled: null,
    },
    customerNote: "",
    kitchenNote: "",
    takeawaySubmissionFingerprint: params.fingerprint,
  };
}
