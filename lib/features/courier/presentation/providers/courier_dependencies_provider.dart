// Barrel re-export for every courier-operations dependency provider.
//
// Sprint 5E Part 7 (docs/decisions.md ADR-022): this file used to hold
// all ~90 providers directly (594 lines) — now split by sub-domain into
// sibling files, re-exported here unchanged so every existing
// `import '.../courier_dependencies_provider.dart'` call site (12 of
// them, across screens and `crm_dependencies_provider.dart`) keeps
// working without modification. New code may import this barrel or the
// specific sub-domain file directly — both resolve to the same
// providers.
export 'courier_communication_dependencies_provider.dart';
export 'courier_compensation_dependencies_provider.dart';
export 'courier_core_dependencies_provider.dart';
export 'courier_dispatch_dependencies_provider.dart';
export 'courier_location_tracking_dependencies_provider.dart';
