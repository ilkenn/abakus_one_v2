import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/channel_pricing_policy_repository.dart';

/// The [ChannelPricingPolicyRepository] implementation currently in use —
/// mirrors `bowlBuilderCatalogRepositoryProvider`'s pattern
/// (`bowl_builder_provider.dart`): swapping in a future Firestore-backed,
/// admin-editable implementation is a change to this provider alone, not to
/// any screen or resolver that depends on it.
final channelPricingPolicyRepositoryProvider =
    Provider<ChannelPricingPolicyRepository>((ref) {
  return InMemoryChannelPricingPolicyRepository();
});
