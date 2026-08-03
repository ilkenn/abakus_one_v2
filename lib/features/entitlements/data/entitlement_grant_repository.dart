import '../domain/entitlement_grant.dart';
import '../domain/entitlement_module.dart';
import '../domain/entitlement_scope_type.dart';

abstract interface class EntitlementGrantRepository {
  Future<void> save(EntitlementGrant grant);
  Future<EntitlementGrant?> findById(String id);

  Future<EntitlementGrant?> findByModuleAndScope(
    EntitlementModule module,
    EntitlementScopeType scopeType,
    String scopeId,
  );

  /// Every grant for one scope, across all modules.
  Future<List<EntitlementGrant>> findByScope(
    EntitlementScopeType scopeType,
    String scopeId,
  );
}

class InMemoryEntitlementGrantRepository implements EntitlementGrantRepository {
  InMemoryEntitlementGrantRepository({List<EntitlementGrant> seed = const []})
      : _byId = {for (final grant in seed) grant.id: grant};

  final Map<String, EntitlementGrant> _byId;

  @override
  Future<void> save(EntitlementGrant grant) async => _byId[grant.id] = grant;

  @override
  Future<EntitlementGrant?> findById(String id) async => _byId[id];

  @override
  Future<EntitlementGrant?> findByModuleAndScope(
    EntitlementModule module,
    EntitlementScopeType scopeType,
    String scopeId,
  ) async {
    for (final grant in _byId.values) {
      if (grant.module == module &&
          grant.scopeType == scopeType &&
          grant.scopeId == scopeId) {
        return grant;
      }
    }
    return null;
  }

  @override
  Future<List<EntitlementGrant>> findByScope(
    EntitlementScopeType scopeType,
    String scopeId,
  ) async {
    return List.unmodifiable(
      _byId.values
          .where((g) => g.scopeType == scopeType && g.scopeId == scopeId),
    );
  }
}
