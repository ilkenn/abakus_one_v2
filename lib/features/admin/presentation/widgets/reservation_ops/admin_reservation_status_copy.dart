import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../reservation/domain/models/reservation_status.dart';

/// Operational, staff-facing status copy — Faz R.3A §2. Deliberately
/// distinct from the customer-facing mapping
/// (`reservation_detail_screen.dart`'s own `_statusCopy`): staff needs to
/// know what action is expected of *them* ("Onay Bekliyor" — waiting on
/// staff to act), not what the customer is being told. The raw backend
/// enum is never rendered directly, on either side.
String adminReservationStatusLabel(ReservationStatus status) {
  switch (status) {
    case ReservationStatus.pendingRestaurantApproval:
      return 'Onay Bekliyor';
    case ReservationStatus.changeProposed:
      return 'Müşteri Yanıtı Bekleniyor';
    case ReservationStatus.confirmed:
      return 'Onaylandı';
    case ReservationStatus.rejected:
      return 'Reddedildi';
    case ReservationStatus.cancelled:
      return 'İptal';
    case ReservationStatus.completed:
      return 'Tamamlandı';
    case ReservationStatus.noShow:
      return 'Gelmedi';
  }
}

Color adminReservationStatusColor(ReservationStatus status) {
  switch (status) {
    case ReservationStatus.pendingRestaurantApproval:
    case ReservationStatus.changeProposed:
      return AppColors.warning;
    case ReservationStatus.confirmed:
    case ReservationStatus.completed:
      return AppColors.success;
    case ReservationStatus.rejected:
    case ReservationStatus.cancelled:
      return AppColors.error;
    // Faz R.3B §22 — calm/de-emphasized, never the same loud error red as
    // an outright rejection/cancellation; a no-show is an operational
    // outcome, not a failure of the system.
    case ReservationStatus.noShow:
      return AppColors.textSecondary;
  }
}

IconData adminReservationStatusIcon(ReservationStatus status) {
  switch (status) {
    case ReservationStatus.pendingRestaurantApproval:
      return Icons.hourglass_top_rounded;
    case ReservationStatus.changeProposed:
      return Icons.swap_horiz_rounded;
    case ReservationStatus.confirmed:
      return Icons.check_circle_rounded;
    case ReservationStatus.rejected:
      return Icons.cancel_rounded;
    case ReservationStatus.cancelled:
      return Icons.event_busy_rounded;
    case ReservationStatus.completed:
      return Icons.task_alt_rounded;
    case ReservationStatus.noShow:
      return Icons.person_off_rounded;
  }
}
