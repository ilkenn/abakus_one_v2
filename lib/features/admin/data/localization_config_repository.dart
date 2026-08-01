import '../domain/localization/localization_config.dart';
import '../domain/localization/localization_scope_type.dart';

abstract interface class LocalizationConfigRepository {
  Future<void> save(LocalizationConfig config);
  Future<LocalizationConfig?> findById(String id);

  Future<LocalizationConfig?> findByScope(
    LocalizationScopeType scopeType,
    String scopeId,
  );

  Future<List<LocalizationConfig>> findAll();
}

class InMemoryLocalizationConfigRepository
    implements LocalizationConfigRepository {
  final Map<String, LocalizationConfig> _byId = {};

  @override
  Future<void> save(LocalizationConfig config) async =>
      _byId[config.id] = config;

  @override
  Future<LocalizationConfig?> findById(String id) async => _byId[id];

  @override
  Future<LocalizationConfig?> findByScope(
    LocalizationScopeType scopeType,
    String scopeId,
  ) async {
    for (final config in _byId.values) {
      if (config.scopeType == scopeType && config.scopeId == scopeId) {
        return config;
      }
    }
    return null;
  }

  @override
  Future<List<LocalizationConfig>> findAll() async =>
      List.unmodifiable(_byId.values);
}
