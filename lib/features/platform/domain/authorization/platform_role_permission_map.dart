import 'platform_authorized_action.dart';
import 'platform_role.dart';

/// The role → permission mapping [RealPlatformAuthorizationPolicy]
/// consults — Phase 8 (`docs/decisions.md` ADR-025). Mirrors
/// `RolePermissionMap`'s tiering shape ([PlatformRole.platformAdministrator]
/// ⊂ [PlatformRole.platformOwner]) but is a wholly separate table over
/// [PlatformAuthorizedAction], never merged with the tenant-hierarchy
/// map — "Platform Owner remains completely separated from tenant
/// hierarchy" holds for the permission model itself, not only for the
/// role/session types.
abstract final class PlatformRolePermissionMap {
  PlatformRolePermissionMap._();

  /// The most sensitive platform actions — creating/destroying a tenant,
  /// and granting the platform-owner-adjacent administrator role itself.
  /// Never available to a plain [PlatformRole.platformAdministrator],
  /// mirroring "no manager granting admin unless authorized" one tier up.
  static const Set<PlatformAuthorizedAction> _ownerOnly = {
    PlatformAuthorizedAction.manageTenantOrganizations,
    PlatformAuthorizedAction.managePlatformAdministrators,
  };

  /// Day-to-day platform operation — everything a
  /// [PlatformRole.platformAdministrator] may do without needing owner
  /// escalation.
  static const Set<PlatformAuthorizedAction> _administratorTier = {
    PlatformAuthorizedAction.manageGlobalEntitlementCatalog,
    PlatformAuthorizedAction.managePlatformIntegrationCatalog,
    PlatformAuthorizedAction.viewPlatformAuditCenter,
    PlatformAuthorizedAction.managePlatformRelease,
    PlatformAuthorizedAction.managePlatformMonitoring,
    PlatformAuthorizedAction.managePlatformStoreCompliance,
  };

  static Set<PlatformAuthorizedAction> permissionsFor(PlatformRole role) {
    switch (role) {
      case PlatformRole.platformAdministrator:
        return _administratorTier;
      case PlatformRole.platformOwner:
        return {..._administratorTier, ..._ownerOnly};
    }
  }

  static bool allows(
    Set<PlatformRole> roles,
    PlatformAuthorizedAction action,
  ) {
    for (final role in roles) {
      if (permissionsFor(role).contains(action)) return true;
    }
    return false;
  }
}
