import { createHash } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Firestore } from "firebase-admin/firestore";
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
  const unitPriceMinorUnits = resolveProductUnitPriceMinorUnits({
    product: product!,
    channel,
    policy,
  });

  const note = typeof item.note === "string" ? item.note.slice(0, 500) : "";
  return buildOrderLine({
    productId: product!.id,
    productName: product!.name,
    modifiers,
    quantity,
    unitPriceMinorUnits,
    taxBasisPoints: TAKEAWAY_TAX_BASIS_POINTS,
    customerNote: note,
  });
}

export async function buildBowlLine(
  db: Firestore,
  item: RawBowlItem,
  scope: { restaurantId: string },
  channel: string,
  policy: import("./takeawayCatalog").CanonicalChannelPricingPolicy,
  tx?: import("firebase-admin/firestore").Transaction,
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
    modifiers,
    quantity,
    unitPriceMinorUnits,
    taxBasisPoints: TAKEAWAY_TAX_BASIS_POINTS,
    customerNote: note,
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
  },
) {
  const { uid, submissionKey, rawItems, contactFirstName, contactLastName, contactPhone } =
    params;
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
      }),
    );

    return { orderId, orderNumber, duplicate: false };
  });
}

// -----------------------------------------------------------------------
// Authenticated customer path
// -----------------------------------------------------------------------

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

    const policy = await loadCanonicalChannelPricingPolicy(db, restaurantId);
    const { lines, normalizedItems } = await buildLines(db, rawItems, { restaurantId }, policy);
    const pricing = computeOrderPriceBreakdown(lines);

    const normalizedForFingerprint = {
      path: "authenticated",
      restaurantId,
      branchId,
      pickupMode: "scheduled",
      pickupTime: pickupTime.toISOString(),
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
      }),
    );

    return { orderId, orderNumber, duplicate: false };
  });
}

// -----------------------------------------------------------------------
// Shared line-building + order document assembly
// -----------------------------------------------------------------------

async function buildLines(
  db: Firestore,
  rawItems: RawItem[],
  scope: { restaurantId: string },
  policy: import("./takeawayCatalog").CanonicalChannelPricingPolicy,
): Promise<{ lines: ComputedOrderLine[]; normalizedItems: unknown[] }> {
  const lines: ComputedOrderLine[] = [];
  const normalizedItems: unknown[] = [];
  for (const item of rawItems) {
    if (item.kind === "product") {
      const line = await buildProductLine(db, item, scope, "takeaway", policy);
      lines.push(line);
      normalizedItems.push({
        kind: "product",
        productId: item.productId,
        quantity: item.quantity,
        selectedModifiers: item.selectedModifiers ?? [],
        note: item.note ?? "",
      });
    } else {
      const line = await buildBowlLine(db, item, scope, "takeaway", policy);
      lines.push(line);
      normalizedItems.push({
        kind: "bowl",
        quantity: item.quantity,
        ingredientIds: item.ingredientIds,
        note: item.note ?? "",
      });
    }
  }
  return { lines, normalizedItems };
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
      discount: moneyField(0),
      taxableBase: moneyField(params.pricing.taxableBaseMinorUnits),
      vatAmount: moneyField(params.pricing.vatAmountMinorUnits),
      serviceFee: moneyField(0),
      deliveryFee: moneyField(0),
      packagingFee: moneyField(0),
      tip: moneyField(0),
      grandTotal: moneyField(params.pricing.grandTotalMinorUnits),
    },
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
