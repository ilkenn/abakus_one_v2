import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/branding_audit_entry_repository.dart';
import '../../data/tenant_brand_theme_repository.dart';
import '../../domain/audit/branding_audit_entry.dart';
import '../../domain/audit/branding_audit_event_type.dart';
import '../../domain/brand_channel.dart';
import '../../domain/channel_branding_override.dart';
import '../../domain/tenant_brand_theme.dart';

/// Sets (or clears, by passing an empty override) one [BrandChannel]'s
/// override on top of a tenant's base `TenantBrandTheme` — Phase 8
/// (`docs/decisions.md` ADR-025), tenantOwner-only, organization-scoped,
/// same authorization shape as `SetTenantBrandTheme`. Requires a base
/// theme to already exist — a channel cannot be branded before the
/// tenant's base brand identity is set.
class SetChannelBrandingOverride {
  const SetChannelBrandingOverride({
    required PosAuthorizationPolicy authorizationPolicy,
    required TenantBrandThemeRepository repository,
    required BrandingAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final TenantBrandThemeRepository _repository;
  final BrandingAuditEntryRepository _auditRepository;

  Future<TenantBrandTheme> call({
    required String organizationId,
    required BrandChannel channel,
    required ChannelBrandingOverride override,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageTenantBranding;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kOrganizationIdAuthorizationContextKey: organizationId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findByOrganizationId(organizationId);
    if (existing == null) {
      throw UnknownBrandThemeViolation(organizationId: organizationId);
    }

    final updated = existing.copyWith(
      channelOverrides: {
        ...existing.channelOverrides,
        channel: override,
      },
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(BrandingAuditEntry(
      id: '${updated.id}-audit-channel-${channel.name}-'
          '${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: BrandingAuditEventType.channelBrandingOverrideSet,
      description: 'Channel branding override set for "${channel.name}" on '
          'organization "$organizationId"',
      targetEntityId: updated.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
