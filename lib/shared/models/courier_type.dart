/// AP-6 Sprint 2 — who is actually delivering a `Courier`/an order.
///
/// Lives in `shared/models` rather than either feature's own `domain/` —
/// both `features/courier` (`Courier.type`) and `features/orders`
/// (`Order.courierType`) need this exact same closed set, matching this
/// codebase's own "cross-feature needs go into `core/`/`shared/`" rule
/// (`CLAUDE.md` §3) rather than one feature importing the other's domain.
///
/// - [internal]: our own registered, branch-dispatched courier.
/// - [pool]: a shared, multi-branch courier pool — still dispatched through
///   our own `assignCourierToOrder` flow, just not exclusive to one branch.
/// - [marketplace]: a third-party (Yemeksepeti/Getir-style) courier
///   dispatched by the external platform itself, never through our own
///   manual assignment. `assignCourierToOrder.ts` never hands out a
///   [marketplace]-typed `Courier` and — separately — refuses to reassign
///   any order whose own `courierType` is already [marketplace]
///   (`MarketplaceCourierImmutableViolation`). No marketplace order-intake
///   path exists yet in this codebase (`docs/business_rules.md` BR-MKT-003)
///   — this value, and the order-side guard it enables, are forward
///   groundwork for that future integration, not reachable via any live
///   flow today.
enum CourierType { internal, pool, marketplace }
