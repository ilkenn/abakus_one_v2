import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/reservation_branch_info.dart';
import 'reservation_dependencies_provider.dart';

/// Step 1/2's data source — party size bounds + the branch-configurable
/// area list. A plain `FutureProvider` (not `.family`): this app targets
/// exactly one restaurant/branch, so there is only ever one instance to
/// cache — matches [reservationRestaurantId]/[reservationBranchId]'s own
/// "single-tenant in practice" convention.
final reservationBranchInfoProvider =
    FutureProvider<ReservationBranchInfo>((ref) {
  return ref.read(reservationGatewayProvider).getReservationBranchInfo(
        restaurantId: reservationRestaurantId,
        branchId: reservationBranchId,
      );
});
