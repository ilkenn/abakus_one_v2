import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reservation_gateway.dart';
import '../../data/reservation_repository.dart';

/// The single Abaküs restaurant/branch this customer app targets —
/// matches the same hardcoded, honest-placeholder `'restaurant-1'`/
/// `'branch-1'` convention already established throughout this codebase
/// (`orders_provider.dart`, `takeaway_dependencies_provider.dart`,
/// `submit_customer_order.dart`, `resolve_table_qr_token.dart`), not a new
/// decision — the backend's own multi-tenant design is real, but this
/// customer app is single-tenant in practice today.
const String reservationRestaurantId = 'restaurant-1';
const String reservationBranchId = 'branch-1';

final reservationGatewayProvider = Provider<ReservationGateway>((ref) {
  return const FirebaseReservationGateway();
});

final reservationRepositoryProvider = Provider<ReservationRepository>((ref) {
  return FirestoreReservationRepository();
});
