/// What triggered a [FraudEvidence] capture — FRAUD-F.0. Determines which
/// tenant-anchor shape the record must have (see `FraudEvidence`'s own doc
/// comment): [addressSave] evidence is captured before any order/tenant
/// exists; [orderSubmit] evidence is captured inside a specific tenant's
/// order. Only [addressSave] has a real producer today — [orderSubmit] is
/// reserved for FRAUD-F.2, which is not started (`docs/decisions.md`
/// FRAUD-F.0).
enum FraudEvidenceKind { addressSave, orderSubmit }
