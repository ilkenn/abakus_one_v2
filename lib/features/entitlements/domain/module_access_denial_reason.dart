/// Which of the three independent authorization layers denied a
/// `CheckModuleAccess` call — `null`/absent means granted. Phase 7
/// (`docs/decisions.md` ADR-024) — surfaced to admin UI so a denial reads
/// as "your subscription doesn't include this" vs. "not enabled yet" vs.
/// "you don't have permission," never a single undifferentiated "denied."
enum ModuleAccessDenialReason {
  notEntitled,
  featureDisabled,
  permissionDenied,
}
