/// An [ImportJob]'s lifecycle state — Phase 7 (`docs/decisions.md`
/// ADR-024). Enforced sequence: [pending] -> [parsing] -> [parsed]
/// (or [parseFailed], terminal) -> [draftReady] -> [underReview] ->
/// [approved] (or [rejected], terminal) -> [committing] -> [committed]
/// (or [commitFailed]) -> optionally [rolledBack]. "Source -> direct
/// database write" never happens — [committed] is the only status that
/// follows a real domain-repository write, and it is only reachable
/// after [approved].
enum ImportStatus {
  pending,
  parsing,
  parsed,
  parseFailed,
  draftReady,
  underReview,
  approved,
  rejected,
  committing,
  committed,
  commitFailed,
  rolledBack,
}
