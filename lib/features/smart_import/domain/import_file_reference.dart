/// An opaque reference to an uploaded source file — never raw bytes,
/// mirroring `CustomerPhoto.photoRef`'s established pattern (Phase 6G).
/// No file-storage/upload dependency exists anywhere in this codebase
/// (confirmed during the Phase 7 pre-implementation survey) — this
/// contract exists so the shape is ready once one is wired, not because
/// upload is implemented today.
class ImportFileReference {
  const ImportFileReference({
    required this.id,
    required this.originalFileName,
    this.mimeType,
    this.sizeBytes,
  });

  final String id;
  final String originalFileName;
  final String? mimeType;
  final int? sizeBytes;
}
