import 'import_file_reference.dart';
import 'import_source_type.dart';

/// What an [ImportJob] is parsing, and from where — Phase 7
/// (`docs/decisions.md` ADR-024). Exactly one of [fileReference]/[url]/
/// [rawText] is populated, matching [type]:
/// [ImportSourceType.pdf]/[ImportSourceType.excel]/
/// [ImportSourceType.menuImagePhoto] → [fileReference];
/// [ImportSourceType.websiteUrl]/[ImportSourceType.qrMenuUrl]/
/// [ImportSourceType.marketplaceMenuUrl] → [url];
/// [ImportSourceType.csv]/[ImportSourceType.structuredJson]/
/// [ImportSourceType.manualPaste] → [rawText]. Not enforced by a
/// constructor invariant (would need a sealed-subclass-per-type split
/// for 9 variants) — `ParseImportSource` validates the expected field is
/// present before parsing and throws otherwise.
class ImportSource {
  const ImportSource({
    required this.type,
    this.fileReference,
    this.url,
    this.rawText,
  });

  final ImportSourceType type;
  final ImportFileReference? fileReference;
  final String? url;
  final String? rawText;
}
