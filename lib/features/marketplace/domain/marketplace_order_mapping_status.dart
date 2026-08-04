/// A [MarketplaceOrderMapping]'s lifecycle — Phase 8
/// (`docs/decisions.md` ADR-025). [received] is the initial state (a
/// raw marketplace order arrived, not yet turned into a real internal
/// `Order`); [mapped] means `internalOrderId` is now set; [failed]
/// means mapping could not complete (e.g. an unmapped menu item).
enum MarketplaceOrderMappingStatus { received, mapped, failed }
