import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/exchange_rate_provider.dart';
import '../../../../shared/models/unavailable_exchange_rate_provider.dart';
import '../../data/pos_order_repository.dart';

/// The [PosOrderRepository] currently in use. [InMemoryPosOrderRepository]
/// today — no backend persistence exists yet (see `docs/business_rules.md`
/// and `docs/feature_status.md`). A future Firebase-backed implementation
/// overrides only this provider, mirroring `ordersRepositoryProvider`'s
/// existing shape in this codebase.
final posOrderRepositoryProvider = Provider<PosOrderRepository>((ref) {
  return InMemoryPosOrderRepository();
});

/// The [ExchangeRateProvider] currently in use. Defaults to
/// [UnavailableExchangeRateProvider] — see its own doc comment for why
/// that's the correct, honest default rather than a placeholder rate.
/// Tests override this provider with a fake that returns real numbers.
final exchangeRateProviderProvider = Provider<ExchangeRateProvider>((ref) {
  return const UnavailableExchangeRateProvider();
});
