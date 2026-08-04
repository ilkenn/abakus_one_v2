/// Every kind of external provider the Integration Hub can hold an
/// adapter for — Phase 8 (`docs/decisions.md` ADR-025). Extensible: a
/// future category (delivery-network, accounting, ...) is a new value
/// here, never a parallel adapter interface.
enum IntegrationProviderCategory { marketplace, payment }
