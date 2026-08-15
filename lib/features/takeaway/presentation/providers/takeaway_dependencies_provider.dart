import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../restaurant/presentation/providers/restaurant_operations_dependencies_provider.dart';
import '../../application/use_cases/list_takeaway_eligible_branches.dart';
import '../../data/submit_takeaway_order_gateway.dart';

/// The server-authoritative takeaway order-creation backend — Faz D.3.1
/// migration. Mirrors `tableGuestSessionGatewayProvider`'s exact shape
/// (`table_guest_session_dependencies_provider.dart`).
final submitTakeawayOrderGatewayProvider = Provider<SubmitTakeawayOrderGateway>(
  (ref) => const FirebaseSubmitTakeawayOrderGateway(),
);

final listTakeawayEligibleBranchesProvider =
    Provider<ListTakeawayEligibleBranches>((ref) {
  return ListTakeawayEligibleBranches(
    branchRepository: ref.watch(branchRepositoryProvider),
    channelOperationPolicyRepository:
        ref.watch(channelOperationPolicyRepositoryProvider),
  );
});

/// The Gel Al-eligible branches for [currentOrganizationIdProvider]'s
/// restaurant(s) — resolved through `restaurantRepositoryProvider`, never
/// a hardcoded `'restaurant-1'` literal, so this stays correct the moment
/// a second restaurant/organization is provisioned (today there is
/// exactly one, matching every other "no restaurant/org selection UI
/// exists yet" placeholder already documented in this codebase — the
/// absence of a *literal* is what makes this additive-safe, not an
/// assumption about how many restaurants exist).
final takeawayEligibleBranchesProvider =
    FutureProvider<List<TakeawayEligibleBranch>>((ref) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  final restaurants = await ref.watch(restaurantRepositoryProvider).findAll();
  final orgRestaurants =
      restaurants.where((r) => r.organizationId == organizationId).toList();

  final listBranches = ref.watch(listTakeawayEligibleBranchesProvider);
  final result = <TakeawayEligibleBranch>[];
  for (final restaurant in orgRestaurants) {
    result.addAll(await listBranches.call(restaurant.id));
  }
  return result;
});
