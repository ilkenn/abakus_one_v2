/// Every Integration Hub mutation this codebase records — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors the established
/// per-bounded-context audit pattern (`docs/business_rules.md`
/// BR-AUDIT-009). Marketplace Hub (8I)/Payment Hub (8J)/Credential
/// Management (8K)/Webhook Foundation (8L) each own their own,
/// separate audit trail — the Integration Audit Center (8N) is a
/// read-only projection over all of them, not a shared write-side type.
enum IntegrationAuditEventType {
  tenantIntegrationEnabled,
  tenantIntegrationDisabled,
  // Phase 8K — Credential Management. The audited fact is always "a
  // credential of this kind was stored/revoked for this provider,"
  // never the credential's own value — see `IntegrationCredentialRef`'s
  // own doc comment for why.
  credentialStored,
  credentialRevoked,
}
