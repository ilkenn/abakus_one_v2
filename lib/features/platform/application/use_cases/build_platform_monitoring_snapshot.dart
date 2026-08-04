import '../../../../core/errors/business_rule_violation.dart';
import '../../../admin/data/organization_repository.dart';
import '../../../integrations/data/tenant_integration_configuration_repository.dart';
import '../../data/platform_member_repository.dart';
import '../../domain/authorization/platform_authorization_policy.dart';
import '../../domain/authorization/platform_authorized_action.dart';
import '../../domain/platform_monitoring_snapshot.dart';

/// Builds the cross-tenant [PlatformMonitoringSnapshot] — Phase 8
/// (`docs/decisions.md` ADR-025), "Platform Monitoring foundation."
/// Read-only, computed fresh on every call (no caching, no scheduled
/// job) — mirrors `BuildAdminOverviewSnapshot`'s (Phase 6E) "a pure,
/// computed-fresh read-model" precedent. Gated by
/// `PlatformAuthorizedAction.managePlatformMonitoring` — the wholly
/// separate platform-role stack (Phase 8A), never the tenant-scoped
/// `PosAuthorizationPolicy`.
class BuildPlatformMonitoringSnapshot {
  const BuildPlatformMonitoringSnapshot({
    required PlatformAuthorizationPolicy authorizationPolicy,
    required OrganizationRepository organizationRepository,
    required PlatformMemberRepository platformMemberRepository,
    required TenantIntegrationConfigurationRepository
        tenantIntegrationRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _organizationRepository = organizationRepository,
        _platformMemberRepository = platformMemberRepository,
        _tenantIntegrationRepository = tenantIntegrationRepository;

  final PlatformAuthorizationPolicy _authorizationPolicy;
  final OrganizationRepository _organizationRepository;
  final PlatformMemberRepository _platformMemberRepository;
  final TenantIntegrationConfigurationRepository _tenantIntegrationRepository;

  /// The honest, static list of dormant Phase 8 services — kept here,
  /// not in the domain type, so it's one obvious place to update as
  /// each is eventually wired for real.
  static const _dormantServiceNotes = [
    'Marketplace provider adapters: every provider resolves to '
        'UnconfiguredIntegrationProviderAdapter — no real vendor SDK is '
        'wired for any of the 5 candidate marketplaces.',
    'Payment provider adapters: every provider resolves to '
        'UnconfiguredIntegrationProviderAdapter — no real vendor SDK is '
        'wired for any of the 9 candidate payment gateways.',
    'Webhook signature verification: UnverifiedWebhookSignatureVerifier '
        'always returns false — no cryptographic hashing dependency '
        'exists yet to verify a real signature.',
    'Webhook delivery receipt: no backend exists in this codebase to '
        'actually receive an inbound webhook HTTP request at all.',
  ];

  Future<PlatformMonitoringSnapshot> call({
    required String actorId,
  }) async {
    const action = PlatformAuthorizedAction.managePlatformMonitoring;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorId: actorId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final organizations = await _organizationRepository.findAll();
    final platformMembers = await _platformMemberRepository.findAll();
    final tenantIntegrations = await _tenantIntegrationRepository.findAll();

    return PlatformMonitoringSnapshot(
      organizationCount: organizations.length,
      platformMemberCount: platformMembers.length,
      tenantIntegrationEnabledCount:
          tenantIntegrations.where((c) => c.enabled).length,
      dormantServiceNotes: _dormantServiceNotes,
      generatedAt: DateTime.now(),
    );
  }
}
