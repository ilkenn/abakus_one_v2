import '../domain/tenant_brand_theme.dart';

abstract interface class TenantBrandThemeRepository {
  Future<void> save(TenantBrandTheme theme);
  Future<TenantBrandTheme?> findByOrganizationId(String organizationId);
}

class InMemoryTenantBrandThemeRepository implements TenantBrandThemeRepository {
  final Map<String, TenantBrandTheme> _byOrganizationId = {};

  @override
  Future<void> save(TenantBrandTheme theme) async {
    _byOrganizationId[theme.organizationId] = theme;
  }

  @override
  Future<TenantBrandTheme?> findByOrganizationId(String organizationId) async {
    return _byOrganizationId[organizationId];
  }
}
