import 'package:abakus_one_v2/features/integrations/domain/integration_connection_status.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_adapter.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_category.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnconfiguredIntegrationProviderAdapter', () {
    test('checkConnection always resolves notConfigured, never throws',
        () async {
      const adapter = UnconfiguredIntegrationProviderAdapter(
        category: IntegrationProviderCategory.marketplace,
        providerId: 'yemeksepeti',
        displayName: 'Yemeksepeti',
      );

      final status = await adapter.checkConnection();

      expect(status, IntegrationConnectionStatus.notConfigured);
    });
  });

  group('IntegrationProviderRegistry', () {
    const marketplaceAdapter = UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.marketplace,
      providerId: 'yemeksepeti',
      displayName: 'Yemeksepeti',
    );
    const paymentAdapter = UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'iyzico',
      displayName: 'iyzico',
    );

    test('findByProviderId looks up an adapter by its id', () {
      final registry =
          IntegrationProviderRegistry([marketplaceAdapter, paymentAdapter]);

      expect(registry.findByProviderId('iyzico'), paymentAdapter);
      expect(registry.findByProviderId('unknown'), isNull);
    });

    test('findByCategory filters to only that category', () {
      final registry =
          IntegrationProviderRegistry([marketplaceAdapter, paymentAdapter]);

      final marketplaceOnly =
          registry.findByCategory(IntegrationProviderCategory.marketplace);

      expect(marketplaceOnly, [marketplaceAdapter]);
    });

    test('all returns every registered adapter', () {
      final registry =
          IntegrationProviderRegistry([marketplaceAdapter, paymentAdapter]);

      expect(registry.all, hasLength(2));
    });
  });
}
