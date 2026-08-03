import '../domain/import_draft.dart';

abstract interface class ImportDraftRepository {
  Future<void> save(ImportDraft draft);
  Future<ImportDraft?> findById(String id);
  Future<ImportDraft?> findByImportJobId(String importJobId);
}

class InMemoryImportDraftRepository implements ImportDraftRepository {
  final Map<String, ImportDraft> _byId = {};

  @override
  Future<void> save(ImportDraft draft) async => _byId[draft.id] = draft;

  @override
  Future<ImportDraft?> findById(String id) async => _byId[id];

  @override
  Future<ImportDraft?> findByImportJobId(String importJobId) async {
    for (final draft in _byId.values) {
      if (draft.importJobId == importJobId) return draft;
    }
    return null;
  }
}
