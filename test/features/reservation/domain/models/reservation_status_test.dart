import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/reservation/domain/models/reservation_status.dart';

void main() {
  test('fromName parses every backend-canonical status name', () {
    expect(
      ReservationStatus.fromName('pendingRestaurantApproval'),
      ReservationStatus.pendingRestaurantApproval,
    );
    expect(
      ReservationStatus.fromName('changeProposed'),
      ReservationStatus.changeProposed,
    );
    expect(
      ReservationStatus.fromName('confirmed'),
      ReservationStatus.confirmed,
    );
    expect(
      ReservationStatus.fromName('rejected'),
      ReservationStatus.rejected,
    );
    expect(
      ReservationStatus.fromName('cancelled'),
      ReservationStatus.cancelled,
    );
    expect(
      ReservationStatus.fromName('completed'),
      ReservationStatus.completed,
    );
    expect(
      ReservationStatus.fromName('noShow'),
      ReservationStatus.noShow,
    );
  });

  test('an unrecognized name throws rather than silently defaulting', () {
    expect(
        () => ReservationStatus.fromName('unknownStatus'), throwsArgumentError);
  });

  group('isTerminal — Faz R.3B §1 canonical terminal set', () {
    test('rejected/cancelled/completed/noShow are all terminal', () {
      expect(ReservationStatus.rejected.isTerminal, isTrue);
      expect(ReservationStatus.cancelled.isTerminal, isTrue);
      expect(ReservationStatus.completed.isTerminal, isTrue);
      expect(ReservationStatus.noShow.isTerminal, isTrue);
    });

    test('pendingRestaurantApproval/changeProposed/confirmed are not terminal',
        () {
      expect(ReservationStatus.pendingRestaurantApproval.isTerminal, isFalse);
      expect(ReservationStatus.changeProposed.isTerminal, isFalse);
      expect(ReservationStatus.confirmed.isTerminal, isFalse);
    });
  });
}
