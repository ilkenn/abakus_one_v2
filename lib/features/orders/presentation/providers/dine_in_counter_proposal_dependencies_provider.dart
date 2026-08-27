import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dine_in_counter_proposal_gateway.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_id.dart';
import 'orders_provider.dart';

/// The server-authoritative dine-in line-replacement response backend —
/// AP-3 continuation. Mirrors `submitDineInOrderGatewayProvider`'s exact
/// shape.
final dineInCounterProposalGatewayProvider =
    Provider<DineInCounterProposalGateway>(
  (ref) => const FirebaseDineInCounterProposalGateway(),
);

/// A one-shot read of the CANONICAL [Order] (not the legacy [OrderModel]
/// [ordersProvider] holds) by id — [OrderLineApprovalState]/
/// [DineInCounterProposal] live only on this aggregate (see
/// `OrderFirestoreMapper`'s own doc comment for why). [ordersProvider]'s
/// own [OrderModel] entries are a one-time snapshot taken at submission
/// time and never refreshed, so they can never reflect a staff decision
/// made afterward — this provider exists specifically to be re-fetched
/// (invalidated on a timer by [DineInLineApprovalSection]) so the customer
/// sees staff accept/reject/replacement-proposal decisions without
/// restarting the app. There is no live Firestore stream for orders in
/// this codebase yet (`CanonicalOrderRepository` is one-shot `Future`-based
/// only) — polling is the deliberate, disclosed stand-in until one exists.
final canonicalOrderByIdProvider =
    FutureProvider.autoDispose.family<Order?, String>((ref, orderId) {
  return ref.watch(canonicalOrderRepositoryProvider).findById(
        OrderId(orderId),
      );
});
