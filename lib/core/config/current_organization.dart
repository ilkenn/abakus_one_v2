/// The single-tenant organization id this app currently operates under.
///
/// Faz R.3C: extracted from `features/admin/.../admin_dependencies_provider
/// .dart`'s previously-duplicated `'org-1'` literal into `core/` so
/// `core/device_tokens` (which needs the same value to satisfy
/// `firestore.rules`'s `deviceTokens` `organizationIdUnchanged()` check)
/// can read it without a forbidden `core -> feature` dependency.
/// `currentOrganizationIdProvider` in `admin_dependencies_provider.dart`
/// now wraps this same constant instead of repeating the literal — no
/// behavior change, single source of truth. Multi-tenant resolution
/// (reading the real organization id from staff claims / a real backend)
/// remains explicitly future work, matching every other "single-tenant for
/// now" note already in this codebase.
const String kSingleTenantOrganizationId = 'org-1';
