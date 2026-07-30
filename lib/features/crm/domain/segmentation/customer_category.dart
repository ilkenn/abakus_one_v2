/// A customer's optional, self-selected occupational/lifestyle segment —
/// Sprint 5D's Customer Segmentation Engine. **Completely optional**:
/// [Customer.category] is nullable, and nothing in this feature requires
/// a value to be set.
///
/// Closed enum, extended additively as new categories are approved —
/// the same convention every other taxonomy in this codebase already
/// follows (`CourierFraudSignalType`, `DeliveryFailureReason`, etc.),
/// chosen over a fully free-text field per `CLAUDE.md` §4's "prefer enums
/// over free strings" rule. [other] is the deliberate escape hatch for
/// "a category not yet in this list" — paired with
/// [Customer.customCategoryLabel] for an administrator-reviewable free
/// text note, never a second silent free-text taxonomy.
enum CustomerCategory {
  student,
  bankEmployee,
  officeWorker,
  softwareTechnology,
  healthcare,
  education,
  selfEmployed,
  hospitality,
  logistics,
  other,
  preferNotToSay,
}
