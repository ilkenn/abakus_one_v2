import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/tenant_customer_directory_gateway.dart';
import 'admin_dependencies_provider.dart';

/// AP-3 continuation — one tenant customer's detail read, re-fetched via
/// `ref.invalidate` after a restriction mutation, mirroring
/// `trustedDeviceRepositoryProvider`'s consumers' own "invalidate after
/// write" convention. The list screen (`customer_management_screen.dart`)
/// calls the gateway directly instead of through a provider — it
/// accumulates pages into local state across "Daha Fazla Yükle" taps,
/// which doesn't fit a single `FutureProvider.family`'s one-request-per-key
/// shape as cleanly as this single-customer read does.
final tenantCustomerDetailProvider = FutureProvider.autoDispose
    .family<TenantCustomerDetail, ({String organizationId, String customerId})>(
        (ref, args) {
  final gateway = ref.watch(tenantCustomerDirectoryGatewayProvider);
  return gateway.getDetail(
    organizationId: args.organizationId,
    customerId: args.customerId,
  );
});
