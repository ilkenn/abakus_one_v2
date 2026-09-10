import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../courier/data/courier_dispatch_gateway.dart';
import '../../../courier/data/firestore_courier_repository.dart';
import '../../../courier/domain/dispatch/courier_return_fifo.dart';
import '../../../courier/domain/identity/courier.dart';
import '../../data/delivery_dispatch_order_repository.dart';

/// AP-6 Sprint 2 — the cashier/admin delivery-dispatch surface's own
/// dependency graph. Deliberately its OWN file/providers, never importing
/// `features/courier/presentation/providers/*` — mirrors
/// `courier_core_dependencies_provider.dart`'s own explicit rule ("courier
/// and KDS dependency graphs stay parallel, never sharing a provider
/// file"); this sprint extends that same separation to the POS/admin side.
/// Reuses the courier module's DOMAIN types (`Courier`, `CourierRepository`)
/// directly — only the wiring, not the shapes, stays separate.
final courierDispatchGatewayProvider = Provider<CourierDispatchGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const UnavailableCourierDispatchGateway();
  }
  return const FirebaseCourierDispatchGateway();
});

final firestoreCourierRepositoryProvider =
    Provider<FirestoreCourierRepository>((ref) {
  return FirestoreCourierRepository();
});

final deliveryDispatchOrderRepositoryProvider =
    Provider<DeliveryDispatchOrderRepository>((ref) {
  return FirestoreDeliveryDispatchOrderRepository();
});

/// Live, FIFO-sorted (`CourierReturnFifo.sortAvailableByReturnTime`)
/// available-courier list for [branchId] — the dispatch dialog's own read.
final availableCouriersForBranchProvider = StreamProvider.family(
  (ref, String branchId) {
    return ref
        .watch(firestoreCourierRepositoryProvider)
        .watchByBranchId(branchId)
        .map(CourierReturnFifo.sortAvailableByReturnTime);
  },
);

/// Every courier registered at [branchId], regardless of dispatch status —
/// used by the dispatch screen's own courier-name lookups (an order's
/// `assignedCourierId` needs a display name even for a courier who is no
/// longer `available`).
final allCouriersForBranchProvider = StreamProvider.family<List<Courier>, String>(
  (ref, branchId) {
    return ref.watch(firestoreCourierRepositoryProvider).watchByBranchId(branchId);
  },
);

final assignableDeliveryOrdersProvider = StreamProvider.family(
  (ref, String branchId) {
    return ref
        .watch(deliveryDispatchOrderRepositoryProvider)
        .watchAssignableDeliveryOrders(branchId);
  },
);
