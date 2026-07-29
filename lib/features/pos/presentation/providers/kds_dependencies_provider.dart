import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock_provider.dart';
import '../../application/identity/kitchen_display_device_id_generator.dart';
import '../../application/identity/kitchen_display_session_id_generator.dart';
import '../../application/identity/kitchen_event_id_generator.dart';
import '../../application/identity/kitchen_print_attempt_id_generator.dart';
import '../../application/identity/kitchen_routing_rule_id_generator.dart';
import '../../application/identity/kitchen_work_item_id_generator.dart';
import '../../application/services/in_memory_kitchen_connection_monitor.dart';
import '../../application/services/in_memory_kitchen_synchronization_service.dart';
import '../../data/in_memory_kitchen_event_bus.dart';
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
import '../../domain/kds/kitchen_synchronization_service.dart';

/// Every Phase 4 KDS repository/id-generator/service currently in use —
/// all in-memory today, no real-time backend exists yet
/// (`docs/decisions.md` ADR-016). Bundled in one file, mirroring
/// `cash_dependencies_provider.dart`/`courier_settlement_dependencies_provider.dart`'s
/// own precedent (Sprint 3E/3F) for the same reason: this phase's screens
/// each depend on several of these at once.
final kitchenProjectionRepositoryProvider =
    Provider<KitchenProjectionRepository>((ref) {
  return InMemoryKitchenProjectionRepository();
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
