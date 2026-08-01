/// A [Branch]'s lifecycle state. `active`/`inactive` is reversible
/// (temporarily closed for renovation, off-season, etc.); `archived` is
/// terminal, matching `StaffMemberStatus`'s own reversible-vs-terminal
/// split.
enum BranchStatus { active, inactive, archived }
