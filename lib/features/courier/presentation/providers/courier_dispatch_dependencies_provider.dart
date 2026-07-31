import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock_provider.dart';
import '../../application/identity/courier_dispatch_queue_event_id_generator.dart';
import '../../application/identity/same_destination_group_id_generator.dart';
import '../../application/use_cases/build_courier_dispatch_queue.dart';
import '../../application/use_cases/sync_courier_dispatch_queue.dart';
import '../../data/courier_delivery_sequence_repository.dart';
import '../../data/courier_dispatch_queue_event_repository.dart';
import '../../data/courier_package_blocking_status_repository.dart';
import '../../data/same_destination_group_repository.dart';

/// Sprint 5C — Courier Dispatch & Operations Center dependencies, split
/// out of `courier_dependencies_provider.dart` (Sprint 5E Part 7,
/// `docs/decisions.md` ADR-022) — self-contained, no cross-sub-domain
/// provider references beyond `core/utils/clock_provider.dart`.
final courierDispatchQueueEventRepositoryProvider =
    Provider<CourierDispatchQueueEventRepository>((ref) {
  return InMemoryCourierDispatchQueueEventRepository();
});

final courierDispatchQueueEventIdGeneratorProvider =
    Provider<CourierDispatchQueueEventIdGenerator>((ref) {
  return SequentialCourierDispatchQueueEventIdGenerator();
});

final syncCourierDispatchQueueProvider =
    Provider<SyncCourierDispatchQueue>((ref) {
  return SyncCourierDispatchQueue(
    clock: ref.watch(clockProvider),
    idGenerator: ref.watch(courierDispatchQueueEventIdGeneratorProvider),
    repository: ref.watch(courierDispatchQueueEventRepositoryProvider),
  );
});

final buildCourierDispatchQueueProvider =
    Provider<BuildCourierDispatchQueue>((ref) {
  return BuildCourierDispatchQueue(
    clock: ref.watch(clockProvider),
    repository: ref.watch(courierDispatchQueueEventRepositoryProvider),
  );
});

final courierDeliverySequenceRepositoryProvider =
    Provider<CourierDeliverySequenceRepository>((ref) {
  return InMemoryCourierDeliverySequenceRepository();
});

final sameDestinationGroupRepositoryProvider =
    Provider<SameDestinationGroupRepository>((ref) {
  return InMemorySameDestinationGroupRepository();
});

final sameDestinationGroupIdGeneratorProvider =
    Provider<SameDestinationGroupIdGenerator>((ref) {
  return SequentialSameDestinationGroupIdGenerator();
});

final courierPackageBlockingStatusRepositoryProvider =
    Provider<CourierPackageBlockingStatusRepository>((ref) {
  return InMemoryCourierPackageBlockingStatusRepository();
});
