import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cancel_dine_in_order_gateway.dart';

/// Self-Order QR Faz 4 — the server-authoritative dine-in customer-self-
/// cancel backend. Mirrors `dineInCounterProposalGatewayProvider`'s exact
/// shape/placement.
final cancelDineInOrderGatewayProvider = Provider<CancelDineInOrderGateway>(
  (ref) => FirebaseCancelDineInOrderGateway(),
);
