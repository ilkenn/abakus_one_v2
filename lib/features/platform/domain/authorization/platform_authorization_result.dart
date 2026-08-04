/// The outcome of a [PlatformAuthorizationPolicy] check — deliberately
/// its own type, not a reuse of `AuthorizationResult`
/// (`features/pos/domain/authorization/`), which carries a
/// `requiresManagerApproval` field meaningful only to the tenant-scoped
/// POS approval workflow. Keeping the platform stack free of any import
/// from `features/pos/domain/authorization/` is itself part of "Platform
/// Owner remains completely separated from tenant hierarchy."
class PlatformAuthorizationResult {
  const PlatformAuthorizationResult({required this.granted, this.reason});

  final bool granted;
  final String? reason;
}
