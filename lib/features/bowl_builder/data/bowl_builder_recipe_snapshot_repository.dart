import '../domain/models/bowl_builder_recipe_snapshot.dart';

abstract interface class BowlBuilderRecipeSnapshotRepository {
  Future<void> save(BowlBuilderRecipeSnapshot snapshot);
  Future<BowlBuilderRecipeSnapshot?> findById(String id);
  Future<List<BowlBuilderRecipeSnapshot>> findByContextId(String contextId);
}

class InMemoryBowlBuilderRecipeSnapshotRepository
    implements BowlBuilderRecipeSnapshotRepository {
  final Map<String, BowlBuilderRecipeSnapshot> _byId = {};

  @override
  Future<void> save(BowlBuilderRecipeSnapshot snapshot) async =>
      _byId[snapshot.id] = snapshot;

  @override
  Future<BowlBuilderRecipeSnapshot?> findById(String id) async => _byId[id];

  @override
  Future<List<BowlBuilderRecipeSnapshot>> findByContextId(
      String contextId) async {
    return List.unmodifiable(
      _byId.values.where((s) => s.contextId == contextId),
    );
  }
}
