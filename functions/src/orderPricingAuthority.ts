/**
 * `orderPricingAuthority` — Boncuk Loyalty P2A security fix (2026-08-21).
 *
 * **`pricingAuthority` and `channel` are NOT interchangeable concepts.**
 * `channel` identifies the commercial/order flow
 * (`takeaway`/`delivery`/`reservationPreorder`/`dineInQr`/`dineInStaff`/...)
 * — a client-authored order can freely set it to any value on a create
 * write that satisfies `firestore.rules`' `isOrgMember`/table-guest
 * branches (confirmed: the `isOrgMember` staff/POS branch has no channel
 * restriction other than excluding `delivery`, so a staff actor can create
 * a direct-Firestore `channel: 'takeaway'` or `channel: 'reservationPreorder'`
 * order today — a legitimate, pre-existing capability this fix does not
 * remove). `channel` therefore proves nothing about how the order's
 * `pricing` block was produced, and earlier P2A treated it as if it did —
 * a genuine security gap a review correctly caught.
 *
 * `pricingAuthority` identifies, independently of `channel`, whether the
 * persisted `pricing` block was produced by one of this codebase's
 * approved, trusted SERVER pricing pipelines
 * (`submitTakeawayOrder`/`submitDeliveryOrder`/`reservationPreorder` — all
 * Admin SDK, all bypass `firestore.rules` entirely). `firestore.rules`
 * denies any client `orders` create that supplies this field at all
 * (`clientOrderCreateOmitsPricingAuthority()`), for every channel and every
 * actor — a client-authored order can therefore never legitimately carry
 * it, regardless of what `channel` string it claims.
 *
 * One canonical constant, not a scattered magic string — every trusted
 * writer and every reader (today: `loyaltyOrderEarning.ts`) refers to this
 * single exported value. A future trusted server pricing pipeline for
 * dine-in/POS (once BR-PRICE-002 closes those channels) stamps this same
 * constant, not a new one — that is what lets it join Boncuk earning
 * without redesigning the loyalty engine.
 */
export const ORDER_PRICING_AUTHORITY_SERVER_V1 = "serverV1" as const;
export type OrderPricingAuthority = typeof ORDER_PRICING_AUTHORITY_SERVER_V1;

export function hasServerPricingAuthority(
  orderData: FirebaseFirestore.DocumentData,
): boolean {
  return orderData.pricingAuthority === ORDER_PRICING_AUTHORITY_SERVER_V1;
}
