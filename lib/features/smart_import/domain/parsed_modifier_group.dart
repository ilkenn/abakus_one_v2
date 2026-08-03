import 'parsed_modifier_option.dart';

/// One modifier group extracted from an [ImportSource] — Phase 7
/// (`docs/decisions.md` ADR-024). [isEmbeddedSuggestion] marks a group
/// the normalizer inferred from free text inside a product's
/// description rather than a source that named it explicitly (e.g. "3
/// boyut mevcut: Küçük, Orta, Büyük" inside a description) — "possible
/// modifier groups embedded in product text" must be detected, but a
/// suggestion, always reviewed, never auto-applied like every other
/// parsed entity here.
class ParsedModifierGroup {
  const ParsedModifierGroup({
    required this.tempId,
    required this.name,
    this.options = const [],
    this.isEmbeddedSuggestion = false,
  });

  final String tempId;
  final String name;
  final List<ParsedModifierOption> options;
  final bool isEmbeddedSuggestion;
}
