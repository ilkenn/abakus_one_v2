/// A [CustomerPhoto]'s moderation state — Phase 6G
/// (`docs/decisions.md` ADR-023).
enum CustomerPhotoStatus {
  pendingReview,
  approved,
  rejected,
  removed,
  underReview,
}
