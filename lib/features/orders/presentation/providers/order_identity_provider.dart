import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/identity/order_identity.dart';

/// The [OrderIdentityProvider] currently in use. [InMemoryOrderIdentityProvider]
/// today — deterministic and collision-safe only within this runtime, not
/// a production identity scheme (see its own doc comment). A future
/// backend-backed implementation overrides only this provider; nothing
/// that depends on [OrderIdentityProvider] needs to change when that
/// happens — mirrors `ordersRepositoryProvider`'s existing shape in this
/// codebase.
final orderIdentityProvider = Provider<OrderIdentityProvider>((ref) {
  return InMemoryOrderIdentityProvider();
});
