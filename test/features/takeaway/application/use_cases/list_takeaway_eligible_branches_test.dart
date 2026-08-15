import 'package:abakus_one_v2/features/admin/data/branch_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/branch.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/branch_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/restaurant/data/channel_operation_policy_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_acceptance_mode.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operation_policy.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operational_state.dart';
import 'package:abakus_one_v2/features/takeaway/application/use_cases/list_takeaway_eligible_branches.dart';
import 'package:flutter_test/flutter_test.dart';

Branch _branch({
  String id = 'branch-x',
  String restaurantId = 'restaurant-1',
  BranchStatus status = BranchStatus.active,
  bool emergencyStopped = false,
  Set<String> supportedOrderChannelIds = const {'takeaway'},
}) {
  return Branch(
    id: id,
    restaurantId: restaurantId,
    name: 'Test Branch $id',
    status: status,
    emergencyStopped: emergencyStopped,
    supportedOrderChannelIds: supportedOrderChannelIds,
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  late InMemoryBranchRepository branchRepository;
  late InMemoryChannelOperationPolicyRepository policyRepository;
  late ListTakeawayEligibleBranches useCase;

  setUp(() {
    branchRepository = InMemoryBranchRepository();
    policyRepository = InMemoryChannelOperationPolicyRepository();
    useCase = ListTakeawayEligibleBranches(
      branchRepository: branchRepository,
      channelOperationPolicyRepository: policyRepository,
    );
  });

  test(
      'an active branch supporting takeaway with no policy set is eligible '
      '(unconfigured = open, matching SetChannelOperationalState\'s own '
      'default)', () async {
    await branchRepository.save(_branch(id: 'branch-1'));

    final result = await useCase.call('restaurant-1');

    expect(result, hasLength(1));
    expect(result.single.id, 'branch-1');
  });

  test('a branch not supporting the takeaway channel id is excluded', () async {
    await branchRepository.save(
      _branch(id: 'branch-1', supportedOrderChannelIds: const {'delivery'}),
    );

    final result = await useCase.call('restaurant-1');

    expect(result, isEmpty);
  });

  test('an inactive branch is excluded even if it supports takeaway', () async {
    await branchRepository.save(
      _branch(id: 'branch-1', status: BranchStatus.inactive),
    );

    final result = await useCase.call('restaurant-1');

    expect(result, isEmpty);
  });

  test('an emergency-stopped branch is excluded', () async {
    await branchRepository.save(
      _branch(id: 'branch-1', emergencyStopped: true),
    );

    final result = await useCase.call('restaurant-1');

    expect(result, isEmpty);
  });

  test('a branch whose takeaway ChannelOperationPolicy is closed is excluded',
      () async {
    await branchRepository.save(_branch(id: 'branch-1'));
    await policyRepository.save(
      ChannelOperationPolicy(
        branchId: 'branch-1',
        channel: OrderChannel.takeaway,
        acceptanceMode: ChannelAcceptanceMode.automatic,
        operationalState: ChannelOperationalState.closed,
        updatedAt: DateTime(2026, 8, 10),
        updatedByStaffId: 'staff-1',
        revision: 1,
      ),
    );

    final result = await useCase.call('restaurant-1');

    expect(result, isEmpty);
  });

  test('a branch whose takeaway ChannelOperationPolicy is open is eligible',
      () async {
    await branchRepository.save(_branch(id: 'branch-1'));
    await policyRepository.save(
      ChannelOperationPolicy(
        branchId: 'branch-1',
        channel: OrderChannel.takeaway,
        acceptanceMode: ChannelAcceptanceMode.automatic,
        operationalState: ChannelOperationalState.open,
        updatedAt: DateTime(2026, 8, 10),
        updatedByStaffId: 'staff-1',
        revision: 1,
      ),
    );

    final result = await useCase.call('restaurant-1');

    expect(result, hasLength(1));
  });

  test('a branch of a different restaurant is not returned', () async {
    await branchRepository.save(
      _branch(id: 'branch-other', restaurantId: 'restaurant-2'),
    );

    final result = await useCase.call('restaurant-1');

    expect(result, isEmpty);
  });
}
