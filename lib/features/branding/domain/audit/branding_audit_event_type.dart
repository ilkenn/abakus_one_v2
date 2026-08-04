/// Every Brand Engine mutation this codebase records — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors the established
/// per-bounded-context audit pattern (`docs/business_rules.md`
/// BR-AUDIT-009).
enum BrandingAuditEventType {
  tenantBrandThemeSet,
  channelBrandingOverrideSet,
}
