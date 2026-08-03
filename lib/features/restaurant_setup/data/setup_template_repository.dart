import '../domain/setup_template.dart';

abstract interface class SetupTemplateRepository {
  Future<void> save(SetupTemplate template);
  Future<SetupTemplate?> findById(String id);

  /// Every public (platform-owned) template plus [organizationId]'s own
  /// private ones — never another organization's private templates.
  Future<List<SetupTemplate>> findVisibleTo(String organizationId);
}

class InMemorySetupTemplateRepository implements SetupTemplateRepository {
  InMemorySetupTemplateRepository({List<SetupTemplate> seed = const []})
      : _byId = {for (final template in seed) template.id: template};

  final Map<String, SetupTemplate> _byId;

  @override
  Future<void> save(SetupTemplate template) async =>
      _byId[template.id] = template;

  @override
  Future<SetupTemplate?> findById(String id) async => _byId[id];

  @override
  Future<List<SetupTemplate>> findVisibleTo(String organizationId) async {
    return List.unmodifiable(
      _byId.values.where(
        (t) => t.isPublic || t.ownerOrganizationId == organizationId,
      ),
    );
  }
}
