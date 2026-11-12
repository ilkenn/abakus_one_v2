import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../courier/data/courier_dispatch_gateway.dart';
import '../../../courier/data/firestore_courier_repository.dart';
import '../../../courier/domain/dispatch/courier_return_fifo.dart';
import '../../../courier/domain/identity/courier.dart';
import '../../../orders/domain/models/order.dart';
import '../../data/courier_pool_gateway.dart';
import '../../data/delivery_dispatch_order_repository.dart';
import '../../data/delivery_operations_gateway.dart';
import '../../domain/delivery/courier_delivery_report.dart';
import '../../domain/delivery/delivery_zone.dart';

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
  return FirebaseCourierDispatchGateway();
});

final firestoreCourierRepositoryProvider =
    Provider<FirestoreCourierRepository>((ref) {
  return FirestoreCourierRepository();
});

final deliveryDispatchOrderRepositoryProvider =
    Provider<DeliveryDispatchOrderRepository>((ref) {
  return FirestoreDeliveryDispatchOrderRepository();
});

/// 2026-11-12 — every dispatch read is keyed by organization AND branch:
/// `firestore.rules` only admits an `orders`/`couriers` list query that
/// pins `organizationId` (`isOrgMember(resource.data.organizationId)` must
/// be provable from the query), so a `branchId`-only query was rejected
/// outright on the real backend ("Teslimat siparişleri yüklenemedi").
typedef DispatchScope = ({String organizationId, String branchId});

/// Live, FIFO-sorted (`CourierReturnFifo.sortAvailableByReturnTime`)
/// available-courier list for the branch — the dispatch dialog's own read.
final availableCouriersForBranchProvider =
    StreamProvider.family<List<Courier>, DispatchScope>(
  (ref, scope) {
    return ref
        .watch(firestoreCourierRepositoryProvider)
        .watchByBranchId(
            organizationId: scope.organizationId, branchId: scope.branchId)
        .map(CourierReturnFifo.sortAvailableByReturnTime);
  },
);

/// Every courier registered at [branchId], regardless of dispatch status —
/// used by the dispatch screen's own courier-name lookups (an order's
/// `assignedCourierId` needs a display name even for a courier who is no
/// longer `available`).
final allCouriersForBranchProvider =
    StreamProvider.family<List<Courier>, DispatchScope>(
  (ref, scope) {
    return ref.watch(firestoreCourierRepositoryProvider).watchByBranchId(
        organizationId: scope.organizationId, branchId: scope.branchId);
  },
);

final assignableDeliveryOrdersProvider =
    StreamProvider.family<List<Order>, DispatchScope>(
  (ref, scope) {
    return ref
        .watch(deliveryDispatchOrderRepositoryProvider)
        .watchAssignableDeliveryOrders(
            organizationId: scope.organizationId, branchId: scope.branchId);
  },
);

/// 2026-11-12 (Faz 3a) — "Havuza Gönder" / "Havuzdan Geri Al" and the
/// approve/reject of an external courier's pool request.
final courierPoolGatewayProvider = Provider<CourierPoolGateway>((ref) {
  if (!ref.watch(firebaseReadyProvider)) {
    return const UnavailableCourierPoolGateway();
  }
  return FirebaseCourierPoolGateway();
});

final courierPoolRequestRepositoryProvider =
    Provider<CourierPoolRequestRepository>((ref) {
  return FirestoreCourierPoolRequestRepository();
});

/// The branch's pending external-courier requests, live.
final pendingCourierPoolRequestsProvider = StreamProvider.family<
    List<CourierPoolRequest>, ({String organizationId, String branchId})>(
  (ref, scope) => ref.watch(courierPoolRequestRepositoryProvider).watchPending(
        organizationId: scope.organizationId,
        branchId: scope.branchId,
      ),
);

/// 2026-11-12 (Faz 4) — neighborhood delivery rules and the courier &
/// package report (ADR-080 / ADR-081).
final deliveryOperationsGatewayProvider =
    Provider<DeliveryOperationsGateway>((ref) {
  if (!ref.watch(firebaseReadyProvider)) {
    return const UnavailableDeliveryOperationsGateway();
  }
  return FirebaseDeliveryOperationsGateway();
});

/// The branch's "Teslimat Bölgeleri" (minimum basket / ETA per
/// neighborhood). Invalidate after an edit.
final branchDeliveryZonesProvider =
    FutureProvider.family<BranchDeliveryZones, DispatchScope>(
  (ref, scope) => ref.watch(deliveryOperationsGatewayProvider).listZones(
        organizationId: scope.organizationId,
        branchId: scope.branchId,
      ),
);

/// The report's request: branch + `[from, to)`.
typedef CourierReportQuery = ({
  String organizationId,
  String branchId,
  DateTime from,
  DateTime to,
});

/// "Kurye & Paket Raporu" for a branch and range (server-computed).
final courierDeliveryReportProvider = FutureProvider.autoDispose
    .family<CourierDeliveryReport, CourierReportQuery>(
  (ref, query) => ref.watch(deliveryOperationsGatewayProvider).courierReport(
        organizationId: query.organizationId,
        branchId: query.branchId,
        from: query.from,
        to: query.to,
      ),
);
