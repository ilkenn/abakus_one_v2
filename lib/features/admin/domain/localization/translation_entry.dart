import 'supported_language.dart';
import 'translation_status.dart';

/// One translated string for one `(contentKey, language)` pair — Phase
/// 6N (`docs/decisions.md` ADR-023). Mutable per-record (content/status
/// change in place via `copyWith`), like `CustomerPhoto` — no update
/// history is kept beyond [translationRevision]'s counter.
///
/// [isMachineGenerated] and [isManuallyEdited] are independent markers,
/// not a single enum — a translation can be machine-generated and later
/// manually edited (both become relevant: it started as machine output,
/// a human has since touched it). "Do not overwrite manually edited
/// translations automatically" is enforced by `SetTranslationContent`
/// checking [isManuallyEdited] before accepting a machine-sourced write,
/// not by this class itself.
class TranslationEntry {
  const TranslationEntry({
    required this.id,
    required this.contentKey,
    required this.language,
    this.content,
    this.status = TranslationStatus.draft,
    this.isMachineGenerated = false,
    this.isManuallyEdited = false,
    this.sourceContentRevision = 1,
    required this.translationRevision,
    required this.updatedAt,
    this.updatedByStaffId,
  });

  final String id;

  /// Opaque identifier for the source content being translated (e.g.
  /// `'menu.item.123.name'`) — this codebase has no menu/content-catalog
  /// integration yet; the key is caller-supplied, not resolved against
  /// any real content registry (an honest foundation-only gap, per the
  /// brief's own "architecture and administration foundation only").
  final String contentKey;

  final SupportedLanguage language;
  final String? content;
  final TranslationStatus status;
  final bool isMachineGenerated;
  final bool isManuallyEdited;

  /// The source (master-language) content's own revision this
  /// translation was made against — lets a future consumer detect a
  /// translation that has gone stale because the source text changed.
  /// No source-content revision tracking exists elsewhere in this
  /// codebase yet, so this is always caller-supplied, never derived.
  final int sourceContentRevision;

  final int translationRevision;
  final DateTime updatedAt;
  final String? updatedByStaffId;

  TranslationEntry copyWith({
    String? content,
    TranslationStatus? status,
    bool? isMachineGenerated,
    bool? isManuallyEdited,
    int? sourceContentRevision,
    required int translationRevision,
    required DateTime updatedAt,
    String? updatedByStaffId,
  }) {
    return TranslationEntry(
      id: id,
      contentKey: contentKey,
      language: language,
      content: content ?? this.content,
      status: status ?? this.status,
      isMachineGenerated: isMachineGenerated ?? this.isMachineGenerated,
      isManuallyEdited: isManuallyEdited ?? this.isManuallyEdited,
      sourceContentRevision:
          sourceContentRevision ?? this.sourceContentRevision,
      translationRevision: translationRevision,
      updatedAt: updatedAt,
      updatedByStaffId: updatedByStaffId ?? this.updatedByStaffId,
    );
  }
}
