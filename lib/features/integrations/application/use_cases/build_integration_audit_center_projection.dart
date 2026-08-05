import '../../../../core/errors/business_rule_violation.dart';
import '../../../marketplace/data/marketplace_audit_entry_repository.dart';
import '../../../payment_hub/data/payment_hub_audit_entry_repository.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/integration_audit_entry_repository.dart';
import '../../domain/integration_audit_center_entry.dart';

/// Builds a unified, read-only [IntegrationAuditCenterEntry] projection
/// — Phase 8 (`docs/decisions.md` ADR-025), "Integration Audit."
/// Merges all 3 of Phase 8's integration-adjacent audit trails —
/// Integration Hub (enable/disable, credentials, webhooks — 8H/8K/8L),
/// Marketplace Hub (8I), Payment Hub (8J) — each already supporting an
/// organization-scoped query, retrofitted onto all three as part of
/// this same part since this codebase owns all three (unlike Phase
/// 6M's `BuildAuditCenterProjection`, which explicitly left 4 *other*
/// bounded contexts' audit trails unretrofitted as separate, larger
/// work for their own owners).
///
/// **No server-side date-range/actor/domain filtering exists** — every
/// filter is applied client-side after fetching each source's full
/// organization-scoped history, the same "future backend query seam"
/// `BuildAuditCenterProjection` already documents.
///
/// **Phase 8 closure sprint (`docs/decisions.md` ADR-025)**: independently
/// authorizes itself, identically to `BuildProviderHealthProjection` —
/// never trusts the caller to have already gated access.
class BuildIntegrationAuditCenterProjection {
  const BuildIntegrationAuditCenterProjection({
    required PosAuthorizationPolicy authorizationPolicy,
    required IntegrationAuditEntryRepository integrationAuditRepository,
    required MarketplaceAuditEntryRepository marketplaceAuditRepository,
    required PaymentHubAuditEntryRepository paymentHubAuditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _integrationAuditRepository = integrationAuditRepository,
        _marketplaceAuditRepository = marketplaceAuditRepository,
        _paymentHubAuditRepository = paymentHubAuditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IntegrationAuditEntryRepository _integrationAuditRepository;
  final MarketplaceAuditEntryRepository _marketplaceAuditRepository;
  final PaymentHubAuditEntryRepository _paymentHubAuditRepository;

  Future<List<IntegrationAuditCenterEntry>> call({
    required String organizationId,
    required String actorStaffId,
    String? actorId,
    String? domain,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    const action = PosAuthorizedAction.manageTenantIntegrations;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: actorStaffId,
      context: {kOrganizationIdAuthorizationContextKey: organizationId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final entries = <IntegrationAuditCenterEntry>[];

    final integrationEntries =
        await _integrationAuditRepository.findByOrganizationId(
      organizationId,
    );
    entries.addAll(integrationEntries.map((e) => IntegrationAuditCenterEntry(
          id: e.id,
          domain: 'integration',
          organizationId: e.organizationId,
          actorId: e.actorId,
          description: e.description,
          targetEntityId: e.targetEntityId,
          timestamp: e.timestamp,
        )));

    final marketplaceEntries =
        await _marketplaceAuditRepository.findByOrganizationId(
      organizationId,
    );
    entries.addAll(marketplaceEntries.map((e) => IntegrationAuditCenterEntry(
          id: e.id,
          domain: 'marketplace',
          organizationId: e.organizationId,
          actorId: e.actorId,
          description: e.description,
          targetEntityId: e.targetEntityId,
          timestamp: e.timestamp,
        )));

    final paymentHubEntries =
        await _paymentHubAuditRepository.findByOrganizationId(
      organizationId,
    );
    entries.addAll(paymentHubEntries.map((e) => IntegrationAuditCenterEntry(
          id: e.id,
          domain: 'payment-hub',
          organizationId: e.organizationId,
          actorId: e.actorId,
          description: e.description,
          targetEntityId: e.targetEntityId,
          timestamp: e.timestamp,
        )));

    var filtered = entries.where((e) {
      if (actorId != null && e.actorId != actorId) return false;
      if (domain != null && e.domain != domain) return false;
      if (from != null && e.timestamp.isBefore(from)) return false;
      if (to != null && e.timestamp.isAfter(to)) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (filtered.length > limit) {
      filtered = filtered.sublist(0, limit);
    }
    return filtered;
  }
}
