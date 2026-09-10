/**
 * Mirrors the canonical 11-state order lifecycle machine defined in Dart
 * (`lib/features/orders/domain/models/order_status.dart`,
 * `OrderStatusTransitions`) — Sprint 9F (docs/decisions.md ADR-026).
 *
 * This is a deliberate, minimal duplication, not a shared package: the
 * Flutter app and these Cloud Functions are two different runtimes
 * (Dart vs. Node/TypeScript) with no code-sharing mechanism set up in
 * this repository. Keeping the two tables in sync by hand is an accepted,
 * documented risk for this sprint's scope (see functions/README.md) —
 * the source of truth for the *design* of the state machine remains the
 * Dart file; this is its server-side enforcement mirror.
 */
export type OrderStatus =
  | "created"
  | "pendingConfirmation"
  | "confirmed"
  | "preparing"
  | "ready"
  | "outForDelivery"
  | "served"
  | "completed"
  | "cancelled"
  | "rejected"
  | "refunded"
  // AP-6 Sprint 1 — mirrors the Dart addition (order_status.dart) exactly:
  // a takeaway order accepted while the branch was `paused`, held back
  // from the kitchen until `scheduledFor`. Never the same thing as
  // `pickupMode: "scheduled"` (submitTakeawayOrder.ts) — that's the
  // customer's own chosen pickup time, an independent field.
  | "scheduled"
  // AP-6 Sprint 3 — a consortium/external-merchant delivery order
  // (Order.merchantId set), written directly here by
  // registerConsortiumOrder.ts: our own kitchen never touches it, so it
  // never passes through pendingConfirmation/confirmed/preparing/ready at
  // all. Never confused with the unrelated PackagePreparationStatus/
  // PackageNotReadyForPickupViolation vocabulary in the courier module's
  // own Delivery aggregate — that's a courier's own pickup-confirmation
  // action, a different axis entirely.
  | "readyForPickup";

export const ORDER_STATUSES: readonly OrderStatus[] = [
  "created",
  "pendingConfirmation",
  "confirmed",
  "preparing",
  "ready",
  "outForDelivery",
  "served",
  "completed",
  "cancelled",
  "rejected",
  "refunded",
  "scheduled",
  "readyForPickup",
];

const ALLOWED_TRANSITIONS: Record<OrderStatus, readonly OrderStatus[]> = {
  created: ["pendingConfirmation", "cancelled", "rejected"],
  pendingConfirmation: ["confirmed", "rejected", "cancelled"],
  confirmed: ["preparing", "cancelled"],
  preparing: ["ready", "cancelled"],
  ready: ["outForDelivery", "served", "completed", "cancelled"],
  outForDelivery: ["served", "completed", "cancelled"],
  served: ["completed"],
  completed: ["refunded"],
  cancelled: [],
  rejected: [],
  refunded: [],
  scheduled: ["confirmed", "rejected", "cancelled"],
  readyForPickup: ["outForDelivery", "cancelled", "rejected"],
};

export function canTransition(from: OrderStatus, to: OrderStatus): boolean {
  if (from === to) return false;
  return ALLOWED_TRANSITIONS[from].includes(to);
}

export function isTerminal(status: OrderStatus): boolean {
  return ALLOWED_TRANSITIONS[status].length === 0;
}

export function isOrderStatus(value: unknown): value is OrderStatus {
  return typeof value === "string" && (ORDER_STATUSES as string[]).includes(value);
}
