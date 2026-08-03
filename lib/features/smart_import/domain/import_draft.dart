import 'parsed_menu.dart';

/// The persisted, reviewable draft for one [ImportJob] — Phase 7
/// (`docs/decisions.md` ADR-024). Wraps one [ParsedMenu] snapshot;
/// re-parsing (or the reviewer editing a field, tracked at the use-case
/// level, not modeled as a separate diff type here) produces a new
/// revision, never mutates the prior one in place — mirrors
/// `PackagePreparation`'s append-only-by-revision shape.
class ImportDraft {
  const ImportDraft({
    required this.id,
    required this.importJobId,
    required this.parsedMenu,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String importJobId;
  final ParsedMenu parsedMenu;
  final DateTime createdAt;
  final int revision;

  ImportDraft copyWith({
    required ParsedMenu parsedMenu,
    required int revision,
  }) {
    return ImportDraft(
      id: id,
      importJobId: importJobId,
      parsedMenu: parsedMenu,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
