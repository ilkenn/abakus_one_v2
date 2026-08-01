import '../domain/organization/organization.dart';

abstract interface class OrganizationRepository {
  Future<void> save(Organization organization);
  Future<Organization?> findById(String organizationId);
  Future<List<Organization>> findAll();
}

class InMemoryOrganizationRepository implements OrganizationRepository {
  InMemoryOrganizationRepository({List<Organization> seed = const []})
      : _byId = {for (final org in seed) org.id: org};

  final Map<String, Organization> _byId;

  @override
  Future<void> save(Organization organization) async =>
      _byId[organization.id] = organization;

  @override
  Future<Organization?> findById(String organizationId) async =>
      _byId[organizationId];

  @override
  Future<List<Organization>> findAll() async => List.unmodifiable(_byId.values);
}
