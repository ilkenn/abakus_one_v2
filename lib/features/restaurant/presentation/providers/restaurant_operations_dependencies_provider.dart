import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/floor_plan_id_generator.dart';
import '../../application/identity/restaurant_table_id_generator.dart';
import '../../data/channel_operation_policy_repository.dart';
import '../../data/floor_plan_repository.dart';
import '../../data/restaurant_operations_audit_entry_repository.dart';
import '../../data/restaurant_table_repository.dart';

/// The [FloorPlanRepository] currently in use. [InMemoryFloorPlanRepository]
/// today — no backend persistence exists yet. Mirrors
/// `posOrderRepositoryProvider`'s existing shape.
final floorPlanRepositoryProvider = Provider<FloorPlanRepository>((ref) {
  return InMemoryFloorPlanRepository();
});

final restaurantTableRepositoryProvider =
    Provider<RestaurantTableRepository>((ref) {
  return InMemoryRestaurantTableRepository();
});

final floorPlanIdGeneratorProvider = Provider<FloorPlanIdGenerator>((ref) {
  return SequentialFloorPlanIdGenerator();
});

final restaurantTableIdGeneratorProvider =
    Provider<RestaurantTableIdGenerator>((ref) {
  return SequentialRestaurantTableIdGenerator();
});

final channelOperationPolicyRepositoryProvider =
    Provider<ChannelOperationPolicyRepository>((ref) {
  return InMemoryChannelOperationPolicyRepository();
});

final restaurantOperationsAuditEntryRepositoryProvider =
    Provider<RestaurantOperationsAuditEntryRepository>((ref) {
  return InMemoryRestaurantOperationsAuditEntryRepository();
});
