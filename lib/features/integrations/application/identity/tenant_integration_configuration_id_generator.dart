abstract interface class TenantIntegrationConfigurationIdGenerator {
  String nextTenantIntegrationConfigurationId();
}

class SequentialTenantIntegrationConfigurationIdGenerator
    implements TenantIntegrationConfigurationIdGenerator {
  SequentialTenantIntegrationConfigurationIdGenerator({
    this.prefix = 'tenant-integration',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextTenantIntegrationConfigurationId() => '$prefix-${++_sequence}';
}
