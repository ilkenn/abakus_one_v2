import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/restaurant/data/channel_operation_policy_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_acceptance_mode.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operation_policy.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operational_state.dart';
import 'package:flutter_test/flutter_test.dart';

ChannelOperationPolicy _policy({
  String branchId = 'branch-1',
  OrderChannel channel = OrderChannel.delivery,
  int revision = 1,
  ChannelOperationalState state = ChannelOperationalState.open,
}) {
  return ChannelOperationPolicy(
    branchId: branchId,
    channel: channel,
    acceptanceMode: ChannelAcceptanceMode.automatic,
    operationalState: state,
    updatedAt: DateTime(2026, 7, 29),
    updatedByStaffId: 'staff-1',
    revision: revision,
  );
}

void main() {
  test('findCurrent returns the latest saved revision', () async {
    final repository = InMemoryChannelOperationPolicyRepository();
    await repository.save(_policy(revision: 1));
    await repository
        .save(_policy(revision: 2, state: ChannelOperationalState.busy));

    final current =
        await repository.findCurrent('branch-1', OrderChannel.delivery);

    expect(current!.revision, 2);
    expect(current.operationalState, ChannelOperationalState.busy);
  });

  test('findHistory returns every revision, oldest first', () async {
    final repository = InMemoryChannelOperationPolicyRepository();
    await repository.save(_policy(revision: 1));
    await repository.save(_policy(revision: 2));

    final history =
        await repository.findHistory('branch-1', OrderChannel.delivery);

    expect(history.map((p) => p.revision), [1, 2]);
  });

  test('different channels are stored independently', () async {
    final repository = InMemoryChannelOperationPolicyRepository();
    await repository.save(_policy(channel: OrderChannel.delivery));
    await repository.save(_policy(channel: OrderChannel.takeaway));

    final deliveryCurrent =
        await repository.findCurrent('branch-1', OrderChannel.delivery);
    final takeawayCurrent =
        await repository.findCurrent('branch-1', OrderChannel.takeaway);

    expect(deliveryCurrent!.channel, OrderChannel.delivery);
    expect(takeawayCurrent!.channel, OrderChannel.takeaway);
  });

  test('findAllCurrentForBranch returns the latest of every channel', () async {
    final repository = InMemoryChannelOperationPolicyRepository();
    await repository.save(_policy(channel: OrderChannel.delivery));
    await repository.save(_policy(
        channel: OrderChannel.delivery,
        revision: 2,
        state: ChannelOperationalState.busy));
    await repository.save(_policy(channel: OrderChannel.takeaway));

    final all = await repository.findAllCurrentForBranch('branch-1');

    expect(all, hasLength(2));
    final delivery = all.firstWhere((p) => p.channel == OrderChannel.delivery);
    expect(delivery.revision, 2);
  });
}
