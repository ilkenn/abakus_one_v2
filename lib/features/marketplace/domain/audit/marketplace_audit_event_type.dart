/// Every Marketplace Hub mutation this codebase records — Phase 8
/// (`docs/decisions.md` ADR-025). One shared trail across every
/// sub-concept (account/store/virtual restaurant/mapping) rather than
/// one repository per concern — mirrors `RestaurantOperationsAuditEntry`'s
/// established precedent (Phase 3D, `docs/business_rules.md`
/// BR-AUDIT-005): these are all genuinely "a marketplace-configuration
/// action happened," the same shape of fact with a different [type].
enum MarketplaceAuditEventType {
  accountCreated,
  storeCreated,
  virtualRestaurantCreated,
  branchMapped,
  menuItemMapped,
  orderMappingRecorded,
}
