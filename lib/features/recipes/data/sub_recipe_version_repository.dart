import '../domain/sub_recipe_version.dart';

abstract interface class SubRecipeVersionRepository {
  Future<void> save(SubRecipeVersion version);
  Future<SubRecipeVersion?> findById(String id);
  Future<List<SubRecipeVersion>> findBySubRecipeId(String subRecipeId);
}

class InMemorySubRecipeVersionRepository implements SubRecipeVersionRepository {
  final Map<String, SubRecipeVersion> _byId = {};

  @override
  Future<void> save(SubRecipeVersion version) async =>
      _byId[version.id] = version;

  @override
  Future<SubRecipeVersion?> findById(String id) async => _byId[id];

  @override
  Future<List<SubRecipeVersion>> findBySubRecipeId(String subRecipeId) async {
    return List.unmodifiable(
      _byId.values.where((v) => v.subRecipeId == subRecipeId),
    );
  }
}
