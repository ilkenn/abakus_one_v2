import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/check_delivery_eligibility_gateway.dart';
import '../../data/submit_delivery_order_gateway.dart';

/// The server-authoritative delivery order-creation backend — Paket
/// Servis P.3. Mirrors `submitTakeawayOrderGatewayProvider`'s exact shape.
final submitDeliveryOrderGatewayProvider = Provider<SubmitDeliveryOrderGateway>(
  (ref) => const FirebaseSubmitDeliveryOrderGateway(),
);

/// Advisory-only eligibility precheck — never authorization; see
/// `DeliveryEligibilityResult`'s own doc comment.
final checkDeliveryEligibilityGatewayProvider =
    Provider<CheckDeliveryEligibilityGateway>(
  (ref) => const FirebaseCheckDeliveryEligibilityGateway(),
);
