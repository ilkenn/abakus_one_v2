/// Where an [ImportJob]'s content came from — Phase 7 (`docs/decisions.md`
/// ADR-024). [supportsDeterministicLocalParsing] distinguishes the
/// formats this codebase can honestly parse today (no new dependency,
/// pure Dart) from ones that require a provider seam not implemented
/// anywhere — "unsupported sources must produce an honest 'provider
/// required' result," never a fake/stubbed parse.
enum ImportSourceType {
  pdf,
  excel,
  csv,
  websiteUrl,
  qrMenuUrl,
  marketplaceMenuUrl,
  menuImagePhoto,
  structuredJson,
  manualPaste;

  /// `true` only for [csv]/[structuredJson]/[manualPaste] — this
  /// codebase has no PDF/Excel-parsing package, no HTTP client for URL
  /// sources, and no OCR/vision provider (confirmed absent from
  /// `pubspec.yaml` during the Phase 7 pre-implementation survey).
  /// `ParseImportSource` throws `UnsupportedImportSourceViolation` for
  /// every other value — never a silent no-op or a fabricated result.
  bool get supportsDeterministicLocalParsing =>
      this == ImportSourceType.csv ||
      this == ImportSourceType.structuredJson ||
      this == ImportSourceType.manualPaste;
}
