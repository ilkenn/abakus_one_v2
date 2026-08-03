enum ImportIssueSeverity { info, warning, error }

/// A single normalization/analysis finding attached to a [ParsedMenu]
/// or one of its entities — duplicate categories, conflicting prices,
/// invalid currency, etc. (Phase 7, `docs/decisions.md` ADR-024). "Do
/// not merge records silently. Show suggested merges in the review
/// stage" — a [duplicateOf]-carrying issue is exactly that suggestion,
/// never an automatic merge.
class ImportIssue {
  const ImportIssue({
    required this.id,
    required this.severity,
    required this.code,
    required this.message,
    this.relatedTempId,
    this.duplicateOfTempId,
  });

  final String id;
  final ImportIssueSeverity severity;

  /// A short, stable machine code (e.g. `'duplicate_product'`,
  /// `'invalid_currency'`, `'missing_description'`) — for filtering/
  /// grouping in the review UI, distinct from [message]'s human text.
  final String code;

  final String message;

  /// The parsed entity's `tempId` this issue is about, if any.
  final String? relatedTempId;

  /// For a suggested-duplicate issue: the `tempId` of the *other*
  /// parsed entity it may duplicate — a suggestion the reviewer accepts
  /// or dismisses, never applied automatically.
  final String? duplicateOfTempId;
}
