/// A cross-tenant operational snapshot for platform-level actors —
/// Phase 8 (`docs/decisions.md` ADR-025), "Platform Monitoring."
/// Distinct from Provider Health Monitoring (8M, tenant-scoped, one
/// organization's own provider status) — this is the platform-owner
/// view spanning every tenant, mirroring `SystemHealthAdminScreen`'s
/// (Phase 6O) "real, computed-fresh counts plus an honest static list
/// of what's dormant" shape one tier up the hierarchy.
class PlatformMonitoringSnapshot {
  const PlatformMonitoringSnapshot({
    required this.organizationCount,
    required this.platformMemberCount,
    required this.tenantIntegrationEnabledCount,
    required this.dormantServiceNotes,
    required this.generatedAt,
  });

  final int organizationCount;
  final int platformMemberCount;

  /// The count of `TenantIntegrationConfiguration` records across
  /// *every* tenant with `enabled: true` — a genuinely cross-tenant
  /// aggregate only a platform-level actor should ever compute.
  final int tenantIntegrationEnabledCount;

  /// A static, factual list of dormant/NoOp Phase 8 services — mirrors
  /// `SystemHealthAdminScreen`'s own "static list of dormant/NoOp
  /// integrations rather than a fabricated dynamic health check"
  /// (Phase 6O), applied to what Phase 8 itself introduced.
  final List<String> dormantServiceNotes;

  final DateTime generatedAt;
}
