import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/connectivity/connectivity_plus_network_monitor.dart';
import '../../../../core/services/connectivity/network_connectivity_monitor.dart';
import '../../application/use_cases/sync_offline_dine_in_orders.dart';
import '../../data/dine_in_offline_order_queue_repository.dart';
import '../../data/submit_dine_in_order_gateway.dart';

/// The server-authoritative dine-in order-creation backend — Boncuk
/// Loyalty Program P7-D.1 (2026-08-24). Mirrors
/// `submitDeliveryOrderGatewayProvider`'s exact shape.
final submitDineInOrderGatewayProvider = Provider<SubmitDineInOrderGateway>(
  (ref) => FirebaseSubmitDineInOrderGateway(),
);

/// Self-Order QR Faz 6 — the device's own "am I online" signal.
final networkConnectivityMonitorProvider =
    Provider<NetworkConnectivityMonitor>((ref) {
  return ConnectivityPlusNetworkMonitor();
});

/// Self-Order QR Faz 6 — `FutureProvider` because `SharedPreferences
/// .getInstance()` is itself async, mirroring `receiptPrinterSettingsProvider`
/// 's own exact shape; every consumer reads this once rather than each
/// constructing its own instance, so the whole app shares one queue.
final dineInOfflineOrderQueueRepositoryProvider =
    FutureProvider<DineInOfflineOrderQueueRepository>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SharedPreferencesDineInOfflineOrderQueueRepository(prefs);
});

final syncOfflineDineInOrdersProvider =
    FutureProvider<SyncOfflineDineInOrders>((ref) async {
  final queueRepository =
      await ref.watch(dineInOfflineOrderQueueRepositoryProvider.future);
  return SyncOfflineDineInOrders(
    queueRepository: queueRepository,
    submitGateway: ref.watch(submitDineInOrderGatewayProvider),
  );
});
