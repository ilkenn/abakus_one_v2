/// The lifecycle of one [TranslationEntry] — Phase 6N
/// (`docs/decisions.md` ADR-023). `missing` is the implicit state before
/// any [TranslationEntry] exists for a `(contentKey, language)` pair —
/// never actually stored; `SetTranslationContent` always creates a
/// record already past it.
enum TranslationStatus {
  missing,
  draft,
  needsReview,
  approved,
}
