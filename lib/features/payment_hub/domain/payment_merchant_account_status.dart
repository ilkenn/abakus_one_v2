/// A [PaymentMerchantAccount]'s lifecycle state — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors `StaffMemberStatus`'s/
/// `MarketplaceAccountStatus`'s reversible/terminal distinction, kept
/// as its own enum rather than a shared import — every bounded context
/// in this codebase that needs an account-lifecycle enum declares its
/// own, despite the identical shape (`StaffMemberStatus`,
/// `PlatformMemberStatus`, `MarketplaceAccountStatus`), so a status
/// change in one context's meaning never silently ripples into another.
enum PaymentMerchantAccountStatus { active, suspended, archived }
