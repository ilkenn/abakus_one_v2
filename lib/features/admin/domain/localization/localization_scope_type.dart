/// The level a [LocalizationConfig] applies at — Phase 6N
/// (`docs/decisions.md` ADR-023).
///
/// The brief names "org/brand/branch" as the three scope levels; this
/// codebase's Phase 6D introduced `Organization -> Restaurant -> Branch`
/// with no separate `Brand` entity (a naming gap already precedented by
/// the pre-existing Loyalty/"Wallet" one, `docs/decisions.md`). No other
/// Phase 6 work asked for a restaurant-level scope, so this foundation
/// covers [organization] and [branch] only — the two levels that
/// already have a real, repository-backed entity to scope against.
enum LocalizationScopeType {
  organization,
  branch,
}
