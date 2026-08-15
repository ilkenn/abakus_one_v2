/**
 * Server-side mirror of `DeliveryPaymentPolicy`/
 * `InMemoryDeliveryPaymentPolicyRepository` (Dart) — Faz P.1. Same
 * "no Dart<->TypeScript sharing mechanism" duplication precedent as every
 * other mirrored file in this codebase (see `takeawayPricing.ts`'s own
 * doc comment): the Dart file remains the source of truth for the
 * *design* of this policy; this is its server-side enforcement primitive
 * for a future `submitDeliveryOrder` (P.2/P.3, not implemented yet) to
 * consume.
 *
 * **Exports no callable** — this phase deliberately does not expose a
 * production-capable delivery order-submission endpoint (P.1 §6). This
 * module only provides the pure policy check so it doesn't have to be
 * invented later under time pressure.
 *
 * LOCKED (`docs/business_rules.md`, Faz P.1 §2/§3): initial release is
 * COD-only, exactly these 7 method ids — `bank_transfer`/`gift_voucher`/
 * any online-payment method are deliberately excluded. Independent of a
 * `PaymentMethod`'s own `isActive` flag (this module has no notion of
 * that catalog at all) — a caller resolving an actual checkout must
 * additionally check the method's live `isActive` state itself.
 */

export const DELIVERY_ENABLED_PAYMENT_METHOD_IDS: ReadonlySet<string> = new Set([
  "cash",
  "credit_card",
  "pluxee",
  "multinet",
  "setcard",
  "edenred",
  "metropol_card",
]);

export function isEnabledForDeliveryCheckout(paymentMethodId: string): boolean {
  return DELIVERY_ENABLED_PAYMENT_METHOD_IDS.has(paymentMethodId);
}
