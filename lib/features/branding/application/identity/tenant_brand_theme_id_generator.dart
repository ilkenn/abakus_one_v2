abstract interface class TenantBrandThemeIdGenerator {
  String nextTenantBrandThemeId();
}

class SequentialTenantBrandThemeIdGenerator
    implements TenantBrandThemeIdGenerator {
  SequentialTenantBrandThemeIdGenerator({this.prefix = 'brand-theme'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextTenantBrandThemeId() => '$prefix-${++_sequence}';
}
