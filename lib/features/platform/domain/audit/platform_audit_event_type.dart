/// Every Platform Owner Hub mutation this codebase records — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors `AdminAuditEventType`'s
/// per-bounded-context pattern (`docs/business_rules.md` BR-AUDIT-009)
/// — a wholly separate audit trail from `AdminAuditEntry`, never
/// shared, since platform mutations and tenant mutations are different
/// bounded contexts by design.
enum PlatformAuditEventType {
  platformOwnerBootstrapped,
}
