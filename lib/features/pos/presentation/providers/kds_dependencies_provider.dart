import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../application/identity/kitchen_display_device_id_generator.dart';
import '../../application/identity/kitchen_display_session_id_generator.dart';
import '../../application/identity/kitchen_event_id_generator.dart';
import '../../application/identity/kitchen_print_attempt_id_generator.dart';
import '../../application/identity/kitchen_routing_rule_id_generator.dart';
import '../../application/identity/kitchen_work_item_id_generator.dart';
import '../../application/services/in_memory_kitchen_connection_monitor.dart';
import '../../application/services/in_memory_kitchen_synchronization_service.dart';
import '../../data/firestore_kitchen_work_item_repository.dart';
import '../../data/in_memory_kitchen_event_bus.dart';
import '../../data/kds_station_lock_store.dart';
import '../../data/kitchen_action_gateway.dart';
import '../../data/kitchen_audit_entry_repository.dart';
import '../../data/kitchen_display_device_repository.dart';
import '../../data/kitchen_display_session_repository.dart';
import '../../data/kitchen_event_cursor_repository.dart';
import '../../data/kitchen_event_repository.dart';
import '../../data/kitchen_print_attempt_repository.dart';
import '../../data/kitchen_projection_repository.dart';
import '../../data/kitchen_routing_rule_repository.dart';
import '../../domain/kds/kitchen_connection_monitor.dart';
import '../../domain/kds/kitchen_event_publisher.dart';
import '../../domain/kds/kitchen_event_subscriber.dart';
import '../../domain/kds/kitchen_order_view.dart';
import '../../domain/kds/kitchen_synchronization_service.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../printing/data/print_job_action_gateway.dart';

/// Every Phase 4 KDS repository/id-generator/service currently in use.
/// **AP-5 Sprint 1**: [kitchenProjectionRepositoryProvider] is now
/// [firebaseReadyProvider]-gated, mirroring `kitchenTicketRepositoryProvider`
/// (`kitchen_ticket_dependencies_provider.dart`) exactly — real
/// [FirestoreKitchenWorkItemRepository] once Firebase is ready,
/// [InMemoryKitchenProjectionRepository] fallback otherwise (`flutter
/// test`, pre-bootstrap). Every other provider below is still in-memory —
/// station routing rules, printer attempts, and the device/session/event
/// sync layer have no real backend yet (tracked, not silently implied
/// done). Bundled in one file, mirroring
/// `cash_dependencies_provider.dart`/`courier_settlement_dependencies_provider.dart`'s
/// own precedent (Sprint 3E/3F) for the same reason: this phase's screens
/// each depend on several of these at once.
final kitchenProjectionRepositoryProvider =
    Provider<KitchenProjectionRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return InMemoryKitchenProjectionRepository();
  }
  return FirestoreKitchenWorkItemRepository();
});

/// KDS Device Station Locking — the physical device's local, restart-
/// durable station filter lock. Deliberately NOT gated by
/// [firebaseReadyProvider]: `SharedPreferences` works standalone whether or
/// not Firebase is ready, unlike every other provider in this file.
final kdsStationLockStoreProvider =
    FutureProvider<KdsStationLockStore>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SharedPreferencesKdsStationLockStore(prefs);
});

/// AP-5 Sprint 1 — the real backend boundary for kitchen work-item
/// transitions (`transitionKitchenWorkItem` callable) and the follow-on
/// order-status advance. Unlike [kitchenProjectionRepositoryProvider],
/// this has no in-memory fallback: mirrors `PosActionGateway`'s own
/// `UnavailablePosActionGateway` precedent — a fail-closed "not available
/// yet" rather than a silent local simulation once Firebase readiness is
/// what gates whether a transition is real at all.
final kitchenActionGatewayProvider = Provider<KitchenActionGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const UnavailableKitchenActionGateway();
  }
  return const FirebaseKitchenActionGateway();
});

/// AP-5 Sprint 4 — the real backend boundary for opening/driving a
/// `PrintJob` (`requestPrintJob`/`recordPrintOutcome` callables). Same
/// fail-closed shape as [kitchenActionGatewayProvider]: no in-memory
/// simulation once Firebase readiness gates whether printing is real.
final printJobActionGatewayProvider = Provider<PrintJobActionGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const UnavailablePrintJobActionGateway();
  }
  return const FirebasePrintJobActionGateway();
});

final kitchenEventRepositoryProvider = Provider<KitchenEventRepository>((ref) {
  return InMemoryKitchenEventRepository();
});

final kitchenEventCursorRepositoryProvider =
    Provider<KitchenEventCursorRepository>((ref) {
  return InMemoryKitchenEventCursorRepository();
});

final kitchenDisplayDeviceRepositoryProvider =
    Provider<KitchenDisplayDeviceRepository>((ref) {
  return InMemoryKitchenDisplayDeviceRepository();
});

final kitchenDisplaySessionRepositoryProvider =
    Provider<KitchenDisplaySessionRepository>((ref) {
  return InMemoryKitchenDisplaySessionRepository();
});

final kitchenRoutingRuleRepositoryProvider =
    Provider<KitchenRoutingRuleRepository>((ref) {
  return InMemoryKitchenRoutingRuleRepository();
});

final kitchenAuditEntryRepositoryProvider =
    Provider<KitchenAuditEntryRepository>((ref) {
  return InMemoryKitchenAuditEntryRepository();
});

final kitchenPrintAttemptRepositoryProvider =
    Provider<KitchenPrintAttemptRepository>((ref) {
  return InMemoryKitchenPrintAttemptRepository();
});

final kitchenEventBusProvider = Provider<InMemoryKitchenEventBus>((ref) {
  return InMemoryKitchenEventBus();
});

final kitchenEventPublisherProvider = Provider<KitchenEventPublisher>((ref) {
  return ref.watch(kitchenEventBusProvider);
});

final kitchenEventSubscriberProvider = Provider<KitchenEventSubscriber>((ref) {
  return ref.watch(kitchenEventBusProvider);
});

final kitchenSynchronizationServiceProvider =
    Provider<KitchenSynchronizationService>((ref) {
  return InMemoryKitchenSynchronizationService(
    clock: ref.watch(clockProvider),
    eventRepository: ref.watch(kitchenEventRepositoryProvider),
    cursorRepository: ref.watch(kitchenEventCursorRepositoryProvider),
  );
});

final kitchenConnectionMonitorProvider =
    Provider<KitchenConnectionMonitor>((ref) {
  return InMemoryKitchenConnectionMonitor(
    sessionRepository: ref.watch(kitchenDisplaySessionRepositoryProvider),
    deviceRepository: ref.watch(kitchenDisplayDeviceRepositoryProvider),
  );
});

final kitchenWorkItemIdGeneratorProvider =
    Provider<KitchenWorkItemIdGenerator>((ref) {
  return SequentialKitchenWorkItemIdGenerator();
});

final kitchenEventIdGeneratorProvider =
    Provider<KitchenEventIdGenerator>((ref) {
  return SequentialKitchenEventIdGenerator();
});

final kitchenDisplayDeviceIdGeneratorProvider =
    Provider<KitchenDisplayDeviceIdGenerator>((ref) {
  return SequentialKitchenDisplayDeviceIdGenerator();
});

final kitchenDisplaySessionIdGeneratorProvider =
    Provider<KitchenDisplaySessionIdGenerator>((ref) {
  return SequentialKitchenDisplaySessionIdGenerator();
});

final kitchenRoutingRuleIdGeneratorProvider =
    Provider<KitchenRoutingRuleIdGenerator>((ref) {
  return SequentialKitchenRoutingRuleIdGenerator();
});

final kitchenPrintAttemptIdGeneratorProvider =
    Provider<KitchenPrintAttemptIdGenerator>((ref) {
  return SequentialKitchenPrintAttemptIdGenerator();
});

/// KDS & POS Çift Yönlü Entegrasyon — a live, order-level kitchen-
/// readiness view (`"3/5 hazır"`/`"Hazır"`), reusable by any screen that
/// needs to show an order's kitchen prep status without walking the caller
/// through `kitchenWorkItems` directly. `null` means no kitchen ticket
/// exists yet for this order (a normal state, e.g. still pending
/// approval), not an error.
final kdsOrderStatusProvider =
    StreamProvider.family<KitchenOrderView?, String>((ref, orderId) {
  return ref
      .watch(kitchenProjectionRepositoryProvider)
      .watchByOrderId(OrderId(orderId))
      .map((workItems) {
    if (workItems.isEmpty) return null;
    return KitchenOrderView.build(
      orderId: OrderId(orderId),
      kitchenTicketId: workItems.first.kitchenTicketId,
      workItems: workItems,
    );
  });
});
