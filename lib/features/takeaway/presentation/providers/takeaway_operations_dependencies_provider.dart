import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../data/takeaway_operations_gateway.dart';
import '../../data/takeaway_operations_repository.dart';

/// AP-6 Sprint 1 — staff-facing takeaway operational-mode dependencies
/// (status badge + mode dialog + scheduled-order-count badge). Kept
/// separate from `takeaway_dependencies_provider.dart` (the CUSTOMER
/// ordering flow's own providers — branch selection, order submission):
/// this file is exclusively the cashier/admin console's write+read
/// boundary for `branchTakeawaySettings`, mirroring
/// `kds_dependencies_provider.dart`'s own per-concern file split.
///
/// [takeawayOperationsGatewayProvider] mirrors [printJobActionGatewayProvider]
/// exactly (`kds_dependencies_provider.dart`): fail-closed
/// [UnavailableTakeawayOperationsGateway] until Firebase is ready, no
/// in-memory simulation once readiness gates whether a mode change is real.
final takeawayOperationsGatewayProvider =
    Provider<TakeawayOperationsGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const UnavailableTakeawayOperationsGateway();
  }
  return const FirebaseTakeawayOperationsGateway();
});

final takeawayOperationsRepositoryProvider =
    Provider<TakeawayOperationsRepository>((ref) {
  return FirestoreTakeawayOperationsRepository();
});

/// Live [BranchTakeawaySettings] for [branchId] — `null` while unresolved
/// (read as [TakeawayOperationStatus.active], per that type's own "missing
/// = active" convention).
final branchTakeawaySettingsProvider = StreamProvider.family(
  (ref, String branchId) {
    return ref.watch(takeawayOperationsRepositoryProvider).watchSettings(branchId);
  },
);

/// Live pending-scheduled-order count for [branchId] — the cashier
/// console's badge, hidden entirely by the widget when this is `0`.
final scheduledOrdersCountProvider = StreamProvider.family(
  (ref, String branchId) {
    return ref
        .watch(takeawayOperationsRepositoryProvider)
        .watchScheduledOrdersCount(branchId);
  },
);
