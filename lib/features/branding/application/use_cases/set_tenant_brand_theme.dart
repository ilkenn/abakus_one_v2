import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/branding_audit_entry_repository.dart';
import '../../data/tenant_brand_theme_repository.dart';
import '../../domain/audit/branding_audit_entry.dart';
import '../../domain/audit/branding_audit_event_type.dart';
import '../../domain/brand_asset_set.dart';
import '../../domain/brand_color_palette.dart';
import '../../domain/brand_typography.dart';
import '../../domain/tenant_brand_theme.dart';
import '../identity/tenant_brand_theme_id_generator.dart';

/// Creates or replaces a tenant's `TenantBrandTheme` — Phase 8
/// (`docs/decisions.md` ADR-025), tenantOwner-only
/// (`PosAuthorizedAction.manageTenantBranding`), organization-scoped
/// (`kOrganizationIdAuthorizationContextKey` — see `ActorSession
/// .organizationAccess`'s "no role is exempt" rule). "One codebase,
/// infinite brands": this never touches `AppColors`/`AppTheme` or any
/// compiled Dart constant — it only persists tenant-supplied data.
class SetTenantBrandTheme {
  const SetTenantBrandTheme({
    required PosAuthorizationPolicy authorizationPolicy,
    required TenantBrandThemeIdGenerator idGenerator,
    required TenantBrandThemeRepository repository,
    required BrandingAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final TenantBrandThemeIdGenerator _idGenerator;
  final TenantBrandThemeRepository _repository;
  final BrandingAuditEntryRepository _auditRepository;

  Future<TenantBrandTheme> call({
    required String organizationId,
    required String brandDisplayName,
    required BrandColorPalette colorPalette,
    required BrandTypography typography,
    BrandAssetSet assets = const BrandAssetSet(),
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

    if (!colorPalette.isValid) {
      throw const InvalidBrandColorPaletteViolation();
    }

    final existing = await _repository.findByOrganizationId(organizationId);
    final theme = TenantBrandTheme(
      id: existing?.id ?? _idGenerator.nextTenantBrandThemeId(),
      organizationId: organizationId,
      brandDisplayName: brandDisplayName,
      colorPalette: colorPalette,
      typography: typography,
      assets: assets,
      channelOverrides: existing?.channelOverrides ?? const {},
      createdAt: existing?.createdAt ?? performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(theme);

    await _auditRepository.appendEvent(BrandingAuditEntry(
      id: '${theme.id}-audit-set-${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: BrandingAuditEventType.tenantBrandThemeSet,
      description: 'Brand theme set for organization "$organizationId": '
          '"$brandDisplayName"',
      targetEntityId: theme.id,
      timestamp: performedAt,
    ));

    return theme;
  }
}
