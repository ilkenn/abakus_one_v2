import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../data/courier_oversight_gateway.dart';

/// ADR-085 stage 6B — the panel's courier oversight (payment-method changes).
final courierOversightGatewayProvider =
    Provider<CourierOversightGateway>((ref) {
  if (!ref.watch(firebaseReadyProvider)) {
    return const UnavailableCourierOversightGateway();
  }
  return FirebaseCourierOversightGateway();
});

final courierPaymentChangesProvider = FutureProvider.autoDispose
    .family<List<CourierPaymentChange>, String>((ref, organizationId) {
  return ref
      .watch(courierOversightGatewayProvider)
      .paymentChanges(organizationId: organizationId);
});
