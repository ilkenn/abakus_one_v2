import 'import_source.dart';
import 'import_status.dart';

/// One Smart Import run — Phase 7 (`docs/decisions.md` ADR-024). Scoped
/// to organization, restaurant, and branch (all required — "every import
/// must be scoped to organization, restaurant and branch where
/// applicable," and this codebase's Phase 6D `Organization -> Restaurant
/// -> Branch` hierarchy always has all three for a real branch). Mutable
/// registry entity tracking [status] transitions — never a direct write
/// into `MenuCategoryRepository`/`MenuProductRepository`/any inventory
/// repository at any point in its own lifecycle; only `CommitImportDraft`
/// (after [ImportStatus.approved]) ever calls those.
class ImportJob {
  const ImportJob({
    required this.id,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.source,
    this.status = ImportStatus.pending,
    required this.createdByStaffId,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.errorMessage,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final ImportSource source;
  final ImportStatus status;
  final String createdByStaffId;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// Populated only for [ImportStatus.parseFailed]/[ImportStatus.commitFailed]
  /// — a human-readable, non-sensitive failure summary, never a raw
  /// exception `toString()` (`ErrorMapper`'s own rule extended here).
  final String? errorMessage;

  final int revision;

  ImportJob copyWith({
    ImportStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    String? errorMessage,
    bool clearErrorMessage = false,
    required int revision,
  }) {
    return ImportJob(
      id: id,
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      source: source,
      status: status ?? this.status,
      createdByStaffId: createdByStaffId,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      revision: revision,
    );
  }
}
