import '../domain/rewards/customer_reward_grant.dart';

/// Append-only storage for [CustomerRewardGrant] — no update or delete
/// method exists at all.
abstract interface class CustomerRewardGrantRepository {
  Future<void> append(CustomerRewardGrant grant);
  Future<List<CustomerRewardGrant>> findByCustomerId(String customerId);
}

class InMemoryCustomerRewardGrantRepository
    implements CustomerRewardGrantRepository {
  final List<CustomerRewardGrant> _grants = [];

  @override
  Future<void> append(CustomerRewardGrant grant) async {
    _grants.add(grant);
  }

  @override
  Future<List<CustomerRewardGrant>> findByCustomerId(String customerId) async {
    return List.unmodifiable(
      _grants.where((g) => g.customerId == customerId),
    );
  }
}
