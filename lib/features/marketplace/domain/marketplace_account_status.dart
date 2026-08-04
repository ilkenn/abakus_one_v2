/// A [MarketplaceAccount]'s lifecycle state — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors `StaffMemberStatus`'s
/// reversible/terminal distinction: [suspended] is reversible,
/// [archived] is not.
enum MarketplaceAccountStatus { active, suspended, archived }
