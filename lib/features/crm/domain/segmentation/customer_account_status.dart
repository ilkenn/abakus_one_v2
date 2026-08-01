/// A [Customer]'s account standing — Phase 6F (`docs/decisions.md`
/// ADR-023). `restricted` is reversible (an admin can reinstate) —
/// there is no `archived`/terminal state for a customer account in this
/// codebase yet; that's future work, not fabricated here.
enum CustomerAccountStatus { active, restricted }
