import '../../../admin/data/branch_repository.dart';
import '../../../admin/domain/organization/branch.dart';
import '../../../admin/domain/organization/branch_status.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../restaurant/data/channel_operation_policy_repository.dart';
import '../../../restaurant/domain/models/channel_operational_state.dart';

/// One branch a customer may pick for a Gel Al (takeaway) order —
/// [Branch] plus the one derived fact the screen actually needs, so it
/// never has to re-run the eligibility logic itself.
class TakeawayEligibleBranch {
  final Branch branch;

  const TakeawayEligibleBranch(this.branch);

  String get id => branch.id;
  String get restaurantId => branch.restaurantId;
  String get displayName => branch.name;
}

/// Resolves which of [restaurantId]'s branches a customer may currently
/// select for Gel Al — Faz C. A branch qualifies when all three hold:
///
/// 1. [Branch.status] is [BranchStatus.active] and not
///    [Branch.emergencyStopped].
/// 2. `'takeaway'` is in [Branch.supportedOrderChannelIds] — the branch
///    has takeaway configured at all, independent of whether it's
///    currently open for it.
/// 3. [ChannelOperationPolicy.acceptsNewOrders] for
///    `(branchId, OrderChannel.takeaway)` — or, if no policy has ever been
///    set for that pair, treated as accepting (mirrors
///    `SetChannelOperationalState`'s own `current?.operationalState ??
///    ChannelOperationalState.open` fallback: an unconfigured channel is
///    not the same as a deliberately closed one).
///
/// This is the first real caller of [ChannelOperationPolicyRepository]
/// from customer-facing code — every existing use was admin/staff-only.
class ListTakeawayEligibleBranches {
  const ListTakeawayEligibleBranches({
    required BranchRepository branchRepository,
    required ChannelOperationPolicyRepository channelOperationPolicyRepository,
  })  : _branchRepository = branchRepository,
        _channelOperationPolicyRepository = channelOperationPolicyRepository;

  final BranchRepository _branchRepository;
  final ChannelOperationPolicyRepository _channelOperationPolicyRepository;

  Future<List<TakeawayEligibleBranch>> call(String restaurantId) async {
    final branches = await _branchRepository.findByRestaurantId(restaurantId);
    final result = <TakeawayEligibleBranch>[];

    for (final branch in branches) {
      if (!await _isEligible(branch)) continue;
      result.add(TakeawayEligibleBranch(branch));
    }
    return result;
  }

  Future<bool> _isEligible(Branch branch) async {
    if (branch.status != BranchStatus.active) return false;
    if (branch.emergencyStopped) return false;
    if (!branch.supportedOrderChannelIds.contains(OrderChannel.takeaway.name)) {
      return false;
    }

    final policy = await _channelOperationPolicyRepository.findCurrent(
      branch.id,
      OrderChannel.takeaway,
    );
    final operationalState =
        policy?.operationalState ?? ChannelOperationalState.open;
    return operationalState == ChannelOperationalState.open ||
        operationalState == ChannelOperationalState.busy;
  }
}
