import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/reservation_availability_slot.dart';
import 'reservation_dependencies_provider.dart';

typedef ReservationAvailabilityKey = ({
  String areaId,
  String dateKey, // "YYYY-MM-DD", branch-local
  int partySize,
});

/// Step 4's data source — re-fetched whenever area/date/party-size
/// changes (the record key naturally invalidates/re-runs the request).
/// Advisory only — `available == false` never disables a slot, it only
/// shapes the soft-decline copy (Faz R.2 §8).
final reservationAvailabilityProvider = FutureProvider.family<
    List<ReservationAvailabilitySlot>, ReservationAvailabilityKey>((ref, key) {
  return ref.read(reservationGatewayProvider).getReservationAvailability(
        restaurantId: reservationRestaurantId,
        branchId: reservationBranchId,
        areaId: key.areaId,
        date: key.dateKey,
        partySize: key.partySize,
      );
});
