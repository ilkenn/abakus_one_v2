import '../domain/localization/supported_language.dart';
import '../domain/localization/translation_entry.dart';

abstract interface class TranslationEntryRepository {
  Future<void> save(TranslationEntry entry);
  Future<TranslationEntry?> findById(String id);

  Future<TranslationEntry?> findByContentKeyAndLanguage(
    String contentKey,
    SupportedLanguage language,
  );

  /// Every language's entry for one piece of source content.
  Future<List<TranslationEntry>> findByContentKey(String contentKey);
}

class InMemoryTranslationEntryRepository implements TranslationEntryRepository {
  final Map<String, TranslationEntry> _byId = {};

  @override
  Future<void> save(TranslationEntry entry) async => _byId[entry.id] = entry;

  @override
  Future<TranslationEntry?> findById(String id) async => _byId[id];

  @override
  Future<TranslationEntry?> findByContentKeyAndLanguage(
    String contentKey,
    SupportedLanguage language,
  ) async {
    for (final entry in _byId.values) {
      if (entry.contentKey == contentKey && entry.language == language) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<List<TranslationEntry>> findByContentKey(String contentKey) async {
    return List.unmodifiable(
      _byId.values.where((e) => e.contentKey == contentKey),
    );
  }
}
