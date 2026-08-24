import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/submit_dine_in_order_gateway.dart';

/// The server-authoritative dine-in order-creation backend — Boncuk
/// Loyalty Program P7-D.1 (2026-08-24). Mirrors
/// `submitDeliveryOrderGatewayProvider`'s exact shape.
final submitDineInOrderGatewayProvider = Provider<SubmitDineInOrderGateway>(
  (ref) => const FirebaseSubmitDineInOrderGateway(),
);
