/// One category extracted from an [ImportSource], not yet an authoritative
/// `MenuCategory` — Phase 7 (`docs/decisions.md` ADR-024). [tempId] is
/// scoped to one parse run only, never a real `MenuCategory.id` (assigned
/// only at commit time, by `CommitImportDraft`, through the real
/// `MenuCategory` constructor/repository).
class ParsedCategory {
  const ParsedCategory({
    required this.tempId,
    required this.name,
    this.sortOrder,
    this.sourceReference,
  });

  final String tempId;
  final String name;
  final int? sortOrder;

  /// Free-text pointer back into the source (e.g. a PDF page number, a
  /// CSV row number) — for the reviewer's "where did this come from"
  /// question, never itself the source content.
  final String? sourceReference;
}
