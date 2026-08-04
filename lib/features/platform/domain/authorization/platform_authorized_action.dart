/// Every action [PlatformAuthorizationPolicy] can gate — Phase 8
/// (`docs/decisions.md` ADR-025). A separate enum from
/// `PosAuthorizedAction`: platform actions operate *across* tenants
/// (creating a tenant, curating the global entitlement/integration
/// catalog, platform-wide release/monitoring), never *within* one, so
/// mixing them into the tenant-scoped enum would blur exactly the
/// boundary this phase exists to draw.
enum PlatformAuthorizedAction {
  /// Create, suspend, or archive a tenant [Organization] — the single
  /// highest-stakes platform action, platformOwner-only.
  manageTenantOrganizations,

  /// Grant or revoke the [PlatformRole.platformAdministrator] role
  /// itself — platformOwner-only, mirroring `manageStaffAdminRole`'s
  /// "no manager granting admin unless authorized" precedent one tier
  /// up.
  managePlatformAdministrators,

  /// Curate which `EntitlementModule` values exist and their default
  /// pricing/availability tier — distinct from a tenant owner's
  /// `manageTenantEntitlements` (which only toggles what *their own*
  /// tenant has purchased from this catalog).
  manageGlobalEntitlementCatalog,

  /// Curate which marketplace/payment provider adapters exist at all
  /// (the platform-level allow-list a tenant's own Integration Hub
  /// selections are drawn from) — distinct from a tenant owner's
  /// `manageTenantIntegrations`.
  managePlatformIntegrationCatalog,

  /// Read-only visibility into every tenant's audit trail — a
  /// platform-wide superset of any single tenant's own Audit Center.
  viewPlatformAuditCenter,

  /// App version/store-rollout coordination (Release Readiness
  /// Foundation) — never publishing itself, only the readiness record.
  managePlatformRelease,

  /// Platform-wide operational monitoring (provider health, system
  /// status) across every tenant.
  managePlatformMonitoring,

  /// Store-compliance foundation records (privacy/data-safety/account-
  /// deletion policy content) that apply platform-wide, not per tenant.
  managePlatformStoreCompliance,
}
