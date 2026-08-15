import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/reservation/domain/models/reservation_area.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_draft.dart';

void main() {
  const area = ReservationArea(id: 'area-1', displayName: 'Bahçe');
  final date = DateTime(2026, 8, 20);
  final time = DateTime.utc(2026, 8, 20, 18, 0);

  group('ReservationDraft.isReadyToReview', () {
    test('false when completely empty', () {
      expect(const ReservationDraft().isReadyToReview, isFalse);
    });

    test('false when only some fields are set', () {
      const partial = ReservationDraft(partySize: 2, area: area);
      expect(partial.isReadyToReview, isFalse);
    });

    test('false when contact name fields are blank/whitespace-only', () {
      final draft = ReservationDraft(
        partySize: 2,
        area: area,
        date: date,
        time: time,
        contactFirstName: '   ',
        contactLastName: 'Yılmaz',
      );
      expect(draft.isReadyToReview, isFalse);
    });

    test('true only once every required field is set', () {
      final draft = ReservationDraft(
        partySize: 2,
        area: area,
        date: date,
        time: time,
        contactFirstName: 'Ada',
        contactLastName: 'Yılmaz',
      );
      expect(draft.isReadyToReview, isTrue);
    });
  });

  group('ReservationDraft.copyWith', () {
    test('overrides only the given fields, keeps the rest', () {
      final original = ReservationDraft(
        partySize: 2,
        area: area,
        date: date,
        time: time,
        hasPreorder: true,
        contactFirstName: 'Ada',
        contactLastName: 'Yılmaz',
      );

      final updated = original.copyWith(partySize: 4);

      expect(updated.partySize, 4);
      expect(updated.area, area);
      expect(updated.date, date);
      expect(updated.time, time);
      expect(updated.hasPreorder, isTrue);
      expect(updated.contactFirstName, 'Ada');
      expect(updated.contactLastName, 'Yılmaz');
    });
  });

  group('ReservationDraft.clearingTime', () {
    test('drops time but keeps date and every other field', () {
      final draft = ReservationDraft(
        partySize: 2,
        area: area,
        date: date,
        time: time,
        hasPreorder: true,
        contactFirstName: 'Ada',
        contactLastName: 'Yılmaz',
      );

      final cleared = draft.clearingTime();

      expect(cleared.time, isNull);
      expect(cleared.date, date);
      expect(cleared.partySize, 2);
      expect(cleared.area, area);
      expect(cleared.hasPreorder, isTrue);
      expect(cleared.contactFirstName, 'Ada');
      expect(cleared.contactLastName, 'Yılmaz');
    });
  });

  group('ReservationDraft.clearingDateAndTime', () {
    test('drops both date and time but keeps every other field', () {
      final draft = ReservationDraft(
        partySize: 2,
        area: area,
        date: date,
        time: time,
        hasPreorder: true,
        contactFirstName: 'Ada',
        contactLastName: 'Yılmaz',
      );

      final cleared = draft.clearingDateAndTime();

      expect(cleared.date, isNull);
      expect(cleared.time, isNull);
      expect(cleared.partySize, 2);
      expect(cleared.area, area);
      expect(cleared.hasPreorder, isTrue);
      expect(cleared.contactFirstName, 'Ada');
      expect(cleared.contactLastName, 'Yılmaz');
    });
  });
}
