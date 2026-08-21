import { HttpsError } from "firebase-functions/v2/https";
import type { Firestore, Transaction, DocumentSnapshot, DocumentReference } from "firebase-admin/firestore";
import {
  loadCanonicalMenuProduct,
  loadCanonicalBowlIngredient,
  type CanonicalMenuProduct,
  type CanonicalChannelPricingPolicy,
} from "./takeawayCatalog";
import {
  resolveProductUnitPriceMinorUnits,
  resolveBowlUnitAdjustmentMinorUnits,
  buildOrderLine,
  computeOrderPriceBreakdown,
  type ComputedOrderLine,
  type OrderLineModifierInput,
  type ComputedPriceBreakdown,
} from "./takeawayPricing";
import { canTransition } from "./orderStatus";
import { PREORDER_KITCHEN_RELEASE_LEAD_MINUTES } from "./reservationConfig";
import { ORDER_PRICING_AUTHORITY_SERVER_V1 } from "./orderPricingAuthority";

/**
 * Optional reservation preorder — Faz R.1D.1 (`docs/decisions.md` ADR-027
 * Faz R.1D.1 design). Everything here is called from *inside*
 * `submitReservation.ts`'s own transaction (creation) or from the three
 * transactions that can confirm/cancel a Reservation
 * (`respondToReservation.ts`'s confirm/reject, `respondToProposedChange.ts`'s
 * accept, `reservationSweep.ts`'s response-timeout sweep) — never a
 * standalone entry point, never a client-reachable callable of its own.
 * Mirrors `submitTakeawayOrder.ts`'s own request-parsing / catalog-backed
 * line-building / order-document-assembly shape closely (this codebase's
 * only other precedent for server-authoritative Order pricing) with three
 * deliberate departures, each disclosed and approved before implementation:
 *
 * 1. **Channel is always the literal `"reservationPreorder"`** — never a
 *    parameter threaded in from a caller, so there is no code path that
 *    could accidentally resolve pricing against `"takeaway"` (or any other
 *    channel) instead. `resolveProductUnitPriceMinorUnits`/
 *    `resolveBowlUnitAdjustmentMinorUnits` are channel-keyed lookups with a
 *    zero-adjustment fallback for an unconfigured channel (verified: no
 *    "unknown channel -> takeaway/default" fallback exists anywhere in
 *    `takeawayPricing.ts`/`takeawayCatalog.ts`) — a restaurant's
 *    `channelPricingPolicies` document keys its takeaway adjustment under
 *    `"takeaway"` specifically (real example:
 *    `submitTakeawayOrderRealCatalog.test.ts`'s "+20 TL" fixture), so
 *    `"reservationPreorder"` only ever resolves its own (absent, hence
 *    zero) entry — normal products price at canonical base price, bowls at
 *    canonical ingredient total with zero channel adjustment, and
 *    `pricing.packagingFee`/`pricing.deliveryFee` are structurally always
 *    `moneyField(0)` in `buildPreorderOrderDocument` below, exactly like
 *    `submitTakeawayOrder.ts`'s own breakdown (no channel, including
 *    takeaway, ever populates these) — the "table/base price, no Gel Al
 *    surcharge, no delivery surcharge" product invariant holds by
 *    construction, not by omission.
 * 2. **Every catalog read takes the surrounding transaction** (`tx`) —
 *    `loadCanonicalMenuProduct`/`loadCanonicalBowlIngredient`/
 *    `loadCanonicalChannelPricingPolicy` all now accept an optional `tx`
 *    (`takeawayCatalog.ts`), and every call in this file passes it, so
 *    these reads participate in the surrounding transaction's optimistic-
 *    concurrency read-set — `submitTakeawayOrder.ts` itself is
 *    deliberately left untouched (out of this phase's scope; tracked as a
 *    disclosed technical-debt note in `docs/feature_status.md`).
 * 3. **No independent idempotency fingerprint on the Order.** A preorder
 *    Order's entire existence is gated by `submitReservation.ts`'s own
 *    idempotency check on the *Reservation* document (checked first, before
 *    any line-building) — a retry with the same `submissionKey` never
 *    re-enters this module at all, so there is nothing for a second,
 *    Order-level fingerprint to guard against.
 */

const PREORDER_CHANNEL = "reservationPreorder" as const;
/** Mirrors `TAKEAWAY_TAX_BASIS_POINTS` — the same 10% `TaxPolicy.defaultRate`, channel-independent. */
const PREORDER_TAX_BASIS_POINTS = 1000;
/** Mirrors `submitTakeawayOrder.ts`'s own `MAX_ITEM_QUANTITY`/`MAX_ITEMS_PER_ORDER` — no Dart-side cart cap exists to reuse instead; these are the only established backend precedent (Faz R.1D.1 §16/D6). */
const MAX_ITEM_QUANTITY = 20;
const MAX_ITEMS_PER_ORDER = 50;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

// -----------------------------------------------------------------------
// Request shape — mirrors submitTakeawayOrder.ts's RawItem shape exactly.
// -----------------------------------------------------------------------

interface RawModifierSelection {
  groupId: unknown;
  optionId: unknown;
}

interface RawProductItem {
  kind: "product";
  productId: unknown;
  quantity: unknown;
  selectedModifiers?: unknown;
  note?: unknown;
}

interface RawBowlItem {
  kind: "bowl";
  quantity: unknown;
  ingredientIds: unknown;
  note?: unknown;
}

type RawItem = RawProductItem | RawBowlItem;

export interface ParsedPreorderRequest {
  items: RawItem[];
}

/**
 * Parses the optional `preorder` field of a `submitReservation` request.
 * `undefined`/`null` means "no preorder" — the existing reservation-only
 * request contract is entirely unchanged for a caller that omits this
 * field (Faz R.1D.1 §3/§1's own "reservation preorder is OPTIONAL").
 */
export function parsePreorderRequest(raw: unknown): ParsedPreorderRequest | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "object") invalid("preorder must be an object or null.");
  const data = raw as Record<string, unknown>;
  const rawItems = data.items;
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    invalid("preorder.items must be a non-empty array.");
  }
  if (rawItems.length > MAX_ITEMS_PER_ORDER) invalid("preorder has too many items.");
  const items = (rawItems as Record<string, unknown>[]).map((item) => {
    if (item.kind === "product") {
      return {
        kind: "product" as const,
        productId: item.productId,
        quantity: item.quantity,
        selectedModifiers: item.selectedModifiers,
        note: item.note,
      };
    }
    if (item.kind === "bowl") {
      return {
        kind: "bowl" as const,
        quantity: item.quantity,
        ingredientIds: item.ingredientIds,
        note: item.note,
      };
    }
    return invalid('each preorder item must have kind "product" or "bowl".');
  });
  return { items };
}

function requireValidQuantity(raw: unknown, context: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw)) {
    invalid(`${context}: quantity must be an integer.`);
  }
  const quantity = raw as number;
  if (quantity <= 0) invalid(`${context}: quantity must be positive.`);
  if (quantity > MAX_ITEM_QUANTITY) invalid(`${context}: quantity exceeds the maximum allowed.`);
  return quantity;
}

// -----------------------------------------------------------------------
// Catalog-backed line building — every Firestore read goes through `tx`.
// -----------------------------------------------------------------------

async function resolvePreorderProductModifiers(
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

async function buildPreorderProductLine(
  tx: Transaction,
  db: Firestore,
  item: RawProductItem,
  scope: { restaurantId: string },
  policy: CanonicalChannelPricingPolicy,
): Promise<ComputedOrderLine> {
  if (typeof item.productId !== "string" || item.productId.length === 0) {
    invalid("each preorder product item requires a productId.");
  }
  const productId = item.productId;
  const quantity = requireValidQuantity(item.quantity, `product "${productId}"`);

  const product = await loadCanonicalMenuProduct(db, productId, tx);
  if (!product) invalid(`product "${productId}" does not exist.`);
  if (product!.restaurantId !== scope.restaurantId) {
    invalid(`product "${productId}" does not belong to this restaurant.`);
  }
  if (!product!.isAvailable) invalid(`product "${productId}" is not available.`);

  const modifiers = await resolvePreorderProductModifiers(product!, item.selectedModifiers);
  const unitPriceMinorUnits = resolveProductUnitPriceMinorUnits({
    product: product!,
    channel: PREORDER_CHANNEL,
    policy,
  });

  const note = typeof item.note === "string" ? item.note.slice(0, 500) : "";
  return buildOrderLine({
    productId: product!.id,
    productName: product!.name,
    modifiers,
    quantity,
    unitPriceMinorUnits,
    taxBasisPoints: PREORDER_TAX_BASIS_POINTS,
    customerNote: note,
  });
}

async function buildPreorderBowlLine(
  tx: Transaction,
  db: Firestore,
  item: RawBowlItem,
  scope: { restaurantId: string },
  policy: CanonicalChannelPricingPolicy,
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

  // The channel adjustment applies exactly ONCE per bowl unit — see
  // submitTakeawayOrder.ts's own buildBowlLine for the identical reasoning.
  const unitPriceMinorUnits = resolveBowlUnitAdjustmentMinorUnits({ channel: PREORDER_CHANNEL, policy });

  const note = typeof item.note === "string" ? item.note.slice(0, 500) : "";
  return buildOrderLine({
    productId: "custom_bowl",
    productName: "Kendi Bowlun",
    modifiers,
    quantity,
    unitPriceMinorUnits,
    taxBasisPoints: PREORDER_TAX_BASIS_POINTS,
    customerNote: note,
  });
}

/**
 * Pure, DB-free normalization of the raw request shape — used both for
 * `submitReservation.ts`'s idempotency fingerprint (computed *before* the
 * transaction even opens, so it must not depend on a DB read) and, via
 * `buildPreorderLines` below, as the actual normalized-items result
 * returned alongside the priced lines. A single source of truth for the
 * shape guarantees the two never drift apart.
 */
export function normalizePreorderItems(rawItems: RawItem[]): unknown[] {
  return rawItems.map((item) =>
    item.kind === "product"
      ? {
          kind: "product",
          productId: item.productId,
          quantity: item.quantity,
          selectedModifiers: item.selectedModifiers ?? [],
          note: item.note ?? "",
        }
      : {
          kind: "bowl",
          quantity: item.quantity,
          ingredientIds: item.ingredientIds,
          note: item.note ?? "",
        },
  );
}

/**
 * Builds every preorder line, sequentially (`for`, not `Promise.all`) —
 * every `tx.get()` this performs still lands before `submitReservation.ts`
 * ever calls `tx.set`, because this function itself is only ever awaited
 * from that transaction's own read phase, before any of its writes.
 */
export async function buildPreorderLines(
  tx: Transaction,
  db: Firestore,
  rawItems: RawItem[],
  scope: { restaurantId: string },
  policy: CanonicalChannelPricingPolicy,
): Promise<{ lines: ComputedOrderLine[]; normalizedItems: unknown[] }> {
  const lines: ComputedOrderLine[] = [];
  for (const item of rawItems) {
    lines.push(
      item.kind === "product"
        ? await buildPreorderProductLine(tx, db, item, scope, policy)
        : await buildPreorderBowlLine(tx, db, item, scope, policy),
    );
  }
  return { lines, normalizedItems: normalizePreorderItems(rawItems) };
}

export function computePreorderPriceBreakdown(lines: ComputedOrderLine[]): ComputedPriceBreakdown {
  return computeOrderPriceBreakdown(lines);
}

// -----------------------------------------------------------------------
// Deterministic Reservation <-> Order linkage (Faz R.1D.1 §5/§9, D3)
// -----------------------------------------------------------------------

/**
 * Deterministic from `reservationId` alone — every confirm/reject/sweep
 * call site resolves the linked preorder's document reference this way
 * (or via the `Reservation.preorderOrderId` snapshot, which is always this
 * same value), never from a client-supplied order id (Faz R.1D.1's second
 * guardrail: "confirm/reject/sweep kodu client'tan order id kabul etmesin").
 */
export function derivePreorderOrderId(reservationId: string): string {
  return `reservation-preorder-${reservationId}`;
}

function deriveOrderNumber(orderId: string): string {
  return `RP-${orderId.slice(orderId.length - 8).toUpperCase()}`;
}

export function resolvePreorderOrderRef(db: Firestore, reservationId: string): DocumentReference {
  return db.collection("orders").doc(derivePreorderOrderId(reservationId));
}

// -----------------------------------------------------------------------
// Order document assembly (Faz R.1D.1 §7)
// -----------------------------------------------------------------------

export function buildPreorderOrderDocument(params: {
  organizationId: string;
  orderId: string;
  restaurantId: string;
  branchId: string;
  customerId: string;
  reservationContextId: string;
  lines: ComputedOrderLine[];
  pricing: ComputedPriceBreakdown;
  now: Date;
}) {
  const currencyCode = "TRY";
  const moneyField = (minorUnits: number) => ({ minorUnits, currencyCode });
  const orderNumber = deriveOrderNumber(params.orderId);

  return {
    organizationId: params.organizationId,
    orderId: params.orderId,
    orderNumber,
    status: "pendingConfirmation",
    channel: PREORDER_CHANNEL,
    // Boncuk Loyalty P2A security fix (2026-08-21) — server-stamped only,
    // never accepted from a request parameter. See
    // `functions/src/orderPricingAuthority.ts` for why this is a distinct
    // concept from `channel`.
    pricingAuthority: ORDER_PRICING_AUTHORITY_SERVER_V1,
    branchId: params.branchId,
    restaurantId: params.restaurantId,
    customerId: params.customerId,
    tableId: null,
    // Faz R.1D.1 §2 — no table session exists for this flow.
    tableSessionId: null,
    guestSessionId: null,
    guestAuthUid: null,
    // Faz R.1D.1 D1 — Order.reservationContextId reused, not a new field:
    // "which reservation/table-context this order is scoped to." A
    // reservationPreorder order is created exclusively via Admin SDK inside
    // submitReservation's own transaction, so the dineInQr-only Firestore
    // Rules branch that also reads this field
    // (tableGuestSessionMatchesOrderScope) never sees this channel.
    reservationContextId: params.reservationContextId,
    takeawayEntrySessionId: null,
    pickupMode: null,
    pickupTime: null,
    pickupTimeTimestamp: null,
    // Faz R.1D.1 §7 — never copied from the Reservation's own contact
    // fields; the existing Order model already treats these as nullable
    // (`OrderFirestoreMapper` reads them as `String?`), and the Reservation
    // document itself remains the source of truth for the customer's
    // contact details, reachable via reservationContextId if ever needed.
    contactFirstName: null,
    contactLastName: null,
    contactPhone: null,
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
      // Faz R.1D.1 §1 — structurally zero for every channel today (not a
      // reservationPreorder-specific carve-out); guarantees "no delivery
      // surcharge" for this channel the same way it already does for
      // takeaway/dine-in.
      deliveryFee: moneyField(0),
      // Faz R.1D.1 §1 — structurally zero; guarantees "no Gel Al packaging
      // surcharge" for this channel.
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
    // Faz R.1D.1 §6/§8 — null until the linked Reservation actually
    // confirms; never set at creation time, regardless of submission-time
    // capacity (a full-slot-at-submission Reservation still gets a
    // preorder — Faz R.1D.1 §6's own explicit instruction).
    // Faz R.1D.2 — kitchenReleaseAtTimestamp is the canonical companion
    // Firestore `Timestamp` field (mirrors `pickupTime`/`pickupTimeTimestamp`'s
    // own established dual-representation precedent in `submitTakeawayOrder.ts`):
    // `kitchenReleaseAt` (ISO string) stays for display/back-compat, this
    // field is what the scheduler's candidate query actually range-filters/
    // orders on. The two are always set/cleared together, never independently.
    kitchenReleaseAt: null,
    kitchenReleaseAtTimestamp: null,
  };
}

// -----------------------------------------------------------------------
// Confirmation-timing binding (Faz R.1D.1 §8/§9/§10) — the ONE shared
// computation every confirm/accept call site uses.
// -----------------------------------------------------------------------

export interface PreorderKitchenTiming {
  status: "pendingConfirmation" | "confirmed";
  kitchenReleaseAt: Date;
}

/**
 * The canonical release instant for a confirmed reservation — pure
 * arithmetic, no status/boundary decision. Faz R.1D.2 §5 reuses this same
 * function (not a copy) to recompute the *expected* value a stored
 * `kitchenReleaseAt`/`kitchenReleaseAtTimestamp` must exactly match before
 * the scheduler is allowed to release an order, so the two can never drift
 * apart by construction.
 */
export function expectedPreorderKitchenReleaseAt(confirmedTime: Date): Date {
  return new Date(confirmedTime.getTime() - PREORDER_KITCHEN_RELEASE_LEAD_MINUTES * 60_000);
}

/**
 * Exact boundary (locked, re-confirmed explicitly before implementation):
 * `remaining = confirmedTime - now`; `remaining > LEAD` stays
 * `pendingConfirmation` (release is still in the future); `remaining <=
 * LEAD` becomes immediately `confirmed` (KDS-eligible now).
 * `kitchenReleaseAt = confirmedTime - LEAD` always, regardless of branch.
 * Computed entirely from server-supplied `Date`s — `confirmedTime` is
 * always either `reservation.requestedTime` (direct confirm) or
 * `proposal.proposedTime` (proposal accept), both already server-validated
 * minute-aligned Firestore-stored values, and `now` is always `new Date()`
 * taken inside the same transaction — never a client-supplied instant.
 */
export function computePreorderKitchenTiming(confirmedTime: Date, now: Date): PreorderKitchenTiming {
  const leadMs = PREORDER_KITCHEN_RELEASE_LEAD_MINUTES * 60_000;
  const kitchenReleaseAt = expectedPreorderKitchenReleaseAt(confirmedTime);
  const remainingMs = confirmedTime.getTime() - now.getTime();
  return {
    status: remainingMs > leadMs ? "pendingConfirmation" : "confirmed",
    kitchenReleaseAt,
  };
}

/** Reads a Firestore `Timestamp`/ISO-string/`Date` field as a `Date` — the same small per-file helper `respondToReservation.ts`/`respondToProposedChange.ts`/`reservationSweep.ts` each already carry their own copy of. */
function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

function appendStatusHistory(
  existing: unknown,
  entry: { id: string; description: string; previousValue: string; newValue: string; now: Date },
) {
  const history = Array.isArray(existing) ? existing : [];
  return [
    ...history,
    {
      id: entry.id,
      type: "statusChange",
      description: entry.description,
      actor: "system",
      timestamp: entry.now.toISOString(),
      previousValue: entry.previousValue,
      newValue: entry.newValue,
    },
  ];
}

/** A generic order-status-transition audit record, keyed deterministically so a retry of the surrounding transaction (a safe no-op, gated by the same status check that produced this event in the first place) never produces a duplicate. Mirrors `onOrderCreated.ts`'s own `auditEvents` shape (`type: "order.statusChanged"`) — the one existing generic, cross-cutting order-transition audit mechanism, extended to a second call site rather than inventing a new one. */
export interface PreorderAuditEvent {
  id: string;
  data: Record<string, unknown>;
}

export interface PreorderTransitionResult {
  patch: Record<string, unknown>;
  /** `null` when the patch doesn't represent a status change (e.g. only `kitchenReleaseAt` moved) — nothing to audit. */
  auditEvent: PreorderAuditEvent | null;
}

function buildConfirmedAuditEvent(orderData: Record<string, unknown>, orderId: string, now: Date): PreorderAuditEvent {
  return {
    id: `${orderId}-transition-preorder-confirmed`,
    data: {
      organizationId: orderData.organizationId,
      type: "order.statusChanged",
      orderId,
      previousValue: "pendingConfirmation",
      newValue: "confirmed",
      actor: "system",
      timestamp: now.toISOString(),
    },
  };
}

/**
 * Given an *already-read* (`tx.get()`'d, by the caller, before any writes
 * in the surrounding transaction) preorder Order snapshot, returns the
 * merge-patch (plus, when the transition actually fires, a matching
 * `auditEvents` record) to apply for a Reservation confirmation (direct
 * confirm or proposal accept) — or `null` if there is nothing to do (no
 * linked preorder, or it's no longer `pendingConfirmation`: already
 * resolved by a prior/concurrent call, idempotent no-op, never
 * re-transitioned). This function stays pure — it never writes; the caller
 * `tx.set()`s both the order patch and, if present, the `auditEvent` in the
 * same transaction, so the state change and its audit record commit
 * atomically or neither does (Faz R.1D.2's own explicit requirement,
 * mirroring `reservationEvents.ts`'s own "atomic with the transition, not a
 * separate step" reasoning).
 * Read/write are deliberately split like this so every call site can slot
 * the read into its own existing read phase and the write into its own
 * existing write phase, preserving the "all reads before all writes"
 * transaction-wide rule this reservation arc enforces everywhere else.
 */
export function buildPreorderConfirmationPatch(
  preorderDoc: DocumentSnapshot,
  confirmedTime: Date,
  now: Date,
): PreorderTransitionResult | null {
  if (!preorderDoc.exists) return null;
  const data = preorderDoc.data()!;
  if (data.status !== "pendingConfirmation") return null;

  const timing = computePreorderKitchenTiming(confirmedTime, now);
  if (timing.status === "pendingConfirmation") {
    // Still not within the release lead time — only the computed release
    // instant changes (e.g. a proposal accept can move confirmedTime). Not
    // a status change, so no audit event.
    return {
      patch: {
        kitchenReleaseAt: timing.kitchenReleaseAt.toISOString(),
        kitchenReleaseAtTimestamp: timing.kitchenReleaseAt,
      },
      auditEvent: null,
    };
  }

  if (!canTransition("pendingConfirmation", "confirmed")) return null; // defensive; the table already guarantees this.
  return {
    patch: {
      status: "confirmed",
      kitchenReleaseAt: timing.kitchenReleaseAt.toISOString(),
      kitchenReleaseAtTimestamp: timing.kitchenReleaseAt,
      version: (typeof data.version === "number" ? data.version : 1) + 1,
      // Nested-object form (not a dotted "timestamps.confirmed" string key) —
      // `tx.set(ref, patch, { merge: true })` deep-merges nested map fields,
      // so this only ever touches `timestamps.confirmed`, leaving every other
      // sibling (`created`/`preparing`/.../`cancelled`) untouched.
      timestamps: { confirmed: now.toISOString() },
      statusHistory: appendStatusHistory(data.statusHistory, {
        id: `${preorderDoc.id}-transition-preorder-confirmed`,
        description: "Status changed from pendingConfirmation to confirmed",
        previousValue: "pendingConfirmation",
        newValue: "confirmed",
        now,
      }),
    },
    auditEvent: buildConfirmedAuditEvent(data, preorderDoc.id, now),
  };
}

/**
 * Faz R.3B §7 — LOCKED business rule detection: whether a linked preorder
 * Order has already reached the kitchen (or gone beyond), never decided
 * from `kitchenReleaseAt` timestamp presence/absence alone (a timestamp can
 * be *set* on a still-`pendingConfirmation` order without the order having
 * actually been released yet — the scheduler/confirm-time patch always sets
 * it, release is a separate `status` transition). The one, canonical
 * source of truth is the Order's own `status` in the shared `orderStatus.ts`
 * state machine:
 *
 * - `pendingConfirmation` — not yet sent to the kitchen. The only status a
 *   reservation preorder can safely be auto-cancelled from (§6).
 * - `confirmed` and every real downstream kitchen state (`preparing`,
 *   `ready`, `outForDelivery`, `served`, `completed`) — already released /
 *   operational. Blocks customer self-cancellation of the parent
 *   Reservation (§6); never auto-cancelled by a Reservation cancellation of
 *   any kind (staff or customer).
 * - `cancelled`/`rejected`/`refunded` — already terminal. Nothing left to
 *   protect, so this is deliberately NOT "released" in the blocking sense —
 *   a customer may still self-cancel their Reservation freely.
 * - `created` — never a real state for a reservation preorder
 *   (`buildPreorderOrderDocument` always starts at `pendingConfirmation`
 *   directly) and any other/unrecognized status string — fail closed
 *   (treated as released/blocking), the safer default when this function
 *   cannot positively confirm the preorder is still pre-kitchen.
 */
export function isReservationPreorderReleasedToKitchen(status: string): boolean {
  switch (status) {
    case "pendingConfirmation":
      return false;
    case "cancelled":
    case "rejected":
    case "refunded":
      return false;
    case "confirmed":
    case "preparing":
    case "ready":
    case "outForDelivery":
    case "served":
    case "completed":
      return true;
    default:
      return true; // unknown/unexpected status — fail closed.
  }
}

/**
 * Same read/write split as `buildPreorderConfirmationPatch`, for the
 * restaurant-reject and response-timeout-sweep paths (Faz R.1D.1 §12) —
 * cancels a still-`pendingConfirmation` linked preorder, clearing any
 * pending kitchen release. `null` if there is nothing to do (no linked
 * preorder, or already resolved).
 */
export function buildPreorderCancellationPatch(
  preorderDoc: DocumentSnapshot,
  now: Date,
): Record<string, unknown> | null {
  if (!preorderDoc.exists) return null;
  const data = preorderDoc.data()!;
  if (data.status !== "pendingConfirmation") return null;
  if (!canTransition("pendingConfirmation", "cancelled")) return null; // defensive; the table already guarantees this.

  return {
    status: "cancelled",
    kitchenReleaseAt: null,
    kitchenReleaseAtTimestamp: null,
    version: (typeof data.version === "number" ? data.version : 1) + 1,
    timestamps: { cancelled: now.toISOString() },
    statusHistory: appendStatusHistory(data.statusHistory, {
      id: `${preorderDoc.id}-transition-preorder-cancelled`,
      description: "Status changed from pendingConfirmation to cancelled",
      previousValue: "pendingConfirmation",
      newValue: "cancelled",
      now,
    }),
  };
}

// -----------------------------------------------------------------------
// Scheduled KDS release (Faz R.1D.2) — the scheduler's own full
// revalidation chain, never trusting the candidate query's result alone.
// -----------------------------------------------------------------------

/**
 * Every possible outcome the scheduler's per-candidate transaction can
 * reach — `eligible: false` is never an error, only a reason to skip this
 * one candidate (logged as a diagnostic) and move on to the next; nothing
 * here throws. `reason` is always a short, stable machine-readable string
 * (never free text) so tests and logs can assert on it precisely.
 */
export type PreorderKdsReleaseSkipReason =
  | "order-not-found"
  | "wrong-channel"
  | "wrong-order-status"
  | "missing-reservation-context"
  | "missing-kitchen-release-at"
  | "reservation-not-found"
  | "reservation-id-mismatch"
  | "preorder-order-id-mismatch"
  | "reservation-not-confirmed"
  | "missing-confirmed-time"
  | "kitchen-release-at-mismatch"
  | "not-yet-due"
  | "illegal-transition";

export type PreorderKdsReleaseCheck =
  | { eligible: true; reason: "released"; patch: Record<string, unknown>; auditEvent: PreorderAuditEvent }
  | { eligible: false; reason: PreorderKdsReleaseSkipReason };

/**
 * Faz R.1D.2 §4/§5 — the scheduler's own full, independent revalidation of
 * one candidate, given *already-read* (`tx.get()`'d by the caller, before
 * any writes) Order and Reservation snapshots. A candidate surfaced by the
 * bounded query is never released on the query result's own say-so alone —
 * every one of the invariants below is re-checked inside the transaction:
 * the Order still exists, is still the right channel/status, still carries
 * a `reservationContextId`/`kitchenReleaseAt`; the linked Reservation still
 * exists, still points back at this exact Order
 * (`Reservation.preorderOrderId === order.id` — the reverse-link integrity
 * check), is still `confirmed`, and still carries a `confirmedTime`. The
 * canonical expected release instant is *recomputed* from
 * `Reservation.confirmedTime` via `expectedPreorderKitchenReleaseAt` (the
 * exact same function `computePreorderKitchenTiming` itself uses) and must
 * match the stored `kitchenReleaseAtTimestamp` **exactly** — a mismatch
 * (e.g. a bug that let the two drift, or a document tampered with outside
 * the normal write paths) is a data-integrity condition, never silently
 * repaired and never released; it surfaces as `"kitchen-release-at-mismatch"`
 * for a caller to log/alert on. Only once every check passes is the actual
 * `pendingConfirmation -> confirmed` transition (same shape as
 * `buildPreorderConfirmationPatch`'s own confirmed branch — status/version/
 * timestamps.confirmed/statusHistory) returned, alongside its own
 * `auditEvents` record, for the caller to `tx.set()` both atomically.
 */
export function buildPreorderKdsReleasePatch(
  orderDoc: DocumentSnapshot,
  reservationDoc: DocumentSnapshot | null,
  now: Date,
): PreorderKdsReleaseCheck {
  if (!orderDoc.exists) return { eligible: false, reason: "order-not-found" };
  const order = orderDoc.data()!;

  if (order.channel !== "reservationPreorder") return { eligible: false, reason: "wrong-channel" };
  if (order.status !== "pendingConfirmation") return { eligible: false, reason: "wrong-order-status" };

  const reservationContextId = order.reservationContextId as string | null | undefined;
  if (!reservationContextId) return { eligible: false, reason: "missing-reservation-context" };
  if (!order.kitchenReleaseAt || !order.kitchenReleaseAtTimestamp) {
    return { eligible: false, reason: "missing-kitchen-release-at" };
  }

  if (!reservationDoc || !reservationDoc.exists) {
    return { eligible: false, reason: "reservation-not-found" };
  }
  if (reservationDoc.id !== reservationContextId) {
    // Defensive — the caller always looks the Reservation up *by*
    // reservationContextId, so this can only fire if a caller is wired
    // incorrectly, never from real data.
    return { eligible: false, reason: "reservation-id-mismatch" };
  }
  const reservation = reservationDoc.data()!;
  if (reservation.preorderOrderId !== orderDoc.id) {
    return { eligible: false, reason: "preorder-order-id-mismatch" };
  }
  if (reservation.status !== "confirmed") {
    return { eligible: false, reason: "reservation-not-confirmed" };
  }
  if (!reservation.confirmedTime) {
    return { eligible: false, reason: "missing-confirmed-time" };
  }

  const confirmedTime = toDate(reservation.confirmedTime);
  const expectedReleaseAt = expectedPreorderKitchenReleaseAt(confirmedTime);
  const storedReleaseAt = toDate(order.kitchenReleaseAtTimestamp);
  if (storedReleaseAt.getTime() !== expectedReleaseAt.getTime()) {
    return { eligible: false, reason: "kitchen-release-at-mismatch" };
  }
  if (expectedReleaseAt.getTime() > now.getTime()) {
    return { eligible: false, reason: "not-yet-due" };
  }
  if (!canTransition("pendingConfirmation", "confirmed")) {
    return { eligible: false, reason: "illegal-transition" }; // defensive; the table already guarantees this.
  }

  const patch: Record<string, unknown> = {
    status: "confirmed",
    version: (typeof order.version === "number" ? order.version : 1) + 1,
    timestamps: { confirmed: now.toISOString() },
    statusHistory: appendStatusHistory(order.statusHistory, {
      id: `${orderDoc.id}-transition-preorder-confirmed`,
      description: "Status changed from pendingConfirmation to confirmed (scheduled KDS release)",
      previousValue: "pendingConfirmation",
      newValue: "confirmed",
      now,
    }),
  };

  return {
    eligible: true,
    reason: "released",
    patch,
    auditEvent: buildConfirmedAuditEvent(order, orderDoc.id, now),
  };
}
