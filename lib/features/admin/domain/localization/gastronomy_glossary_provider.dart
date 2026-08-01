import 'supported_language.dart';

/// Future seam for a gastronomy-domain glossary (menu/food-specific
/// terminology a general-purpose translation provider would get wrong,
/// e.g. dish names, portion units) — Phase 6N (`docs/decisions.md`
/// ADR-023). No implementation exists; nothing constructs or calls it
/// today, matching [AiTranslationProvider]'s own dormant-contract
/// precedent.
abstract interface class GastronomyGlossaryProvider {
  /// Returns a preferred glossary translation for [term] in
  /// [targetLanguage], or `null` if the term has no glossary entry.
  Future<String?> lookupTerm({
    required String term,
    required SupportedLanguage targetLanguage,
  });
}

/// The only implementation of [GastronomyGlossaryProvider] today —
/// always returns `null`. Not wired into any Riverpod provider.
class EmptyGastronomyGlossaryProvider implements GastronomyGlossaryProvider {
  const EmptyGastronomyGlossaryProvider();

  @override
  Future<String?> lookupTerm({
    required String term,
    required SupportedLanguage targetLanguage,
  }) async =>
      null;
}
