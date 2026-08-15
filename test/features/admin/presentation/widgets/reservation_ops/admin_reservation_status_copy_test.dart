import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/presentation/widgets/reservation_ops/admin_reservation_status_copy.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_status.dart';

void main() {
  test('every ReservationStatus has an approved, non-empty Turkish label', () {
    for (final status in ReservationStatus.values) {
      final label = adminReservationStatusLabel(status);
      expect(label, isNotEmpty);
      expect(label, isNot(equals(status.name)));
    }
  });

  test('status labels are the exact required Faz R.3A copy', () {
    expect(
        adminReservationStatusLabel(
            ReservationStatus.pendingRestaurantApproval),
        'Onay Bekliyor');
    expect(adminReservationStatusLabel(ReservationStatus.changeProposed),
        'Müşteri Yanıtı Bekleniyor');
    expect(
        adminReservationStatusLabel(ReservationStatus.confirmed), 'Onaylandı');
    expect(
        adminReservationStatusLabel(ReservationStatus.rejected), 'Reddedildi');
    expect(adminReservationStatusLabel(ReservationStatus.cancelled), 'İptal');
  });

  test('status labels are the exact required Faz R.3B copy', () {
    expect(
        adminReservationStatusLabel(ReservationStatus.completed), 'Tamamlandı');
    expect(adminReservationStatusLabel(ReservationStatus.noShow), 'Gelmedi');
  });

  test(
      'Faz R.3B §22 — noShow is calm/de-emphasized, never the same loud '
      'error red as rejected/cancelled', () {
    final noShowColor = adminReservationStatusColor(ReservationStatus.noShow);
    final rejectedColor =
        adminReservationStatusColor(ReservationStatus.rejected);
    final cancelledColor =
        adminReservationStatusColor(ReservationStatus.cancelled);

    expect(noShowColor, isNot(equals(rejectedColor)));
    expect(noShowColor, isNot(equals(cancelledColor)));
  });

  test(
      'Faz R.3B §22 — completed reuses the same positive/success tone as confirmed',
      () {
    expect(
      adminReservationStatusColor(ReservationStatus.completed),
      adminReservationStatusColor(ReservationStatus.confirmed),
    );
  });

  test('every status has a distinct icon assigned', () {
    final icons = {
      for (final status in ReservationStatus.values)
        status: adminReservationStatusIcon(status)
    };
    expect(icons.values.toSet().length, ReservationStatus.values.length);
  });

  test(
      'color coding groups pending/changeProposed as warning, confirmed as success, rejected/cancelled as error',
      () {
    final pendingColor = adminReservationStatusColor(
        ReservationStatus.pendingRestaurantApproval);
    final proposedColor =
        adminReservationStatusColor(ReservationStatus.changeProposed);
    final confirmedColor =
        adminReservationStatusColor(ReservationStatus.confirmed);
    final rejectedColor =
        adminReservationStatusColor(ReservationStatus.rejected);
    final cancelledColor =
        adminReservationStatusColor(ReservationStatus.cancelled);

    expect(pendingColor, proposedColor);
    expect(rejectedColor, cancelledColor);
    expect(confirmedColor, isNot(equals(pendingColor)));
    expect(confirmedColor, isNot(equals(rejectedColor)));
  });
}
