/// Every surface the Phase 8 kickoff names as separately brandable —
/// "Loyalty Branding, Push Branding, QR Branding, Email Branding,
/// Receipt Branding, Web Branding" (`docs/decisions.md` ADR-025). Each
/// may optionally override the tenant's base `TenantBrandTheme`; a
/// channel with no override resolves to the base theme unchanged — see
/// `ResolveEffectiveBrandTheme`.
enum BrandChannel { loyalty, push, qrMenu, email, receipt, web }
