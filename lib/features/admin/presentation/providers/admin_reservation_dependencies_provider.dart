import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_reservation_gateway.dart';
import '../../data/admin_reservation_repository.dart';

/// Faz R.3A — mirrors `reservationRestaurantId`/`reservationBranchId`'s
/// own established "single-tenant in practice" placeholder convention
/// (`features/reservation/presentation/providers/
/// reservation_dependencies_provider.dart`) rather than inventing a
/// second one. `currentOrganizationIdProvider`/`currentBranchIdProvider`
/// (`features/admin`/`features/navigation`) are the actual providers used
/// at call sites — these constants exist only for contexts (tests, the
/// gateway's own default arguments) that need a bare value rather than a
/// Riverpod read.
const String adminReservationOrganizationId = 'org-1';
const String adminReservationRestaurantId = 'restaurant-1';
const String adminReservationBranchId = 'branch-1';

final adminReservationGatewayProvider =
    Provider<AdminReservationGateway>((ref) {
  return const FirebaseAdminReservationGateway();
});

final adminReservationRepositoryProvider =
    Provider<AdminReservationRepository>((ref) {
  return FirestoreAdminReservationRepository();
});
