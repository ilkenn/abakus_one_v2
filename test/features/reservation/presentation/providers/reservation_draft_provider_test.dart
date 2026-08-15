import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/reservation/domain/models/reservation_area.dart';
import 'package:abakus_one_v2/features/reservation/presentation/providers/reservation_draft_provider.dart';

void main() {
  const area = ReservationArea(id: 'area-1', displayName: 'Bahçe');
  final date = DateTime(2026, 8, 20);
  final time = DateTime.utc(2026, 8, 20, 18, 0);

  test('starts empty', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(reservationDraftProvider), const IsEmptyDraft());
  });

  test('setPartySize updates only partySize', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(reservationDraftProvider.notifier).setPartySize(4);

    expect(container.read(reservationDraftProvider).partySize, 4);
  });

  test('setArea updates only area', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(reservationDraftProvider.notifier).setArea(area);

    expect(container.read(reservationDraftProvider).area, area);
  });

  test('setDate invalidates a previously chosen time', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reservationDraftProvider.notifier);

    notifier.setDate(date);
    notifier.setTime(time);
    expect(container.read(reservationDraftProvider).time, time);

    notifier.setDate(DateTime(2026, 8, 21));

    expect(container.read(reservationDraftProvider).time, isNull);
    expect(
        container.read(reservationDraftProvider).date, DateTime(2026, 8, 21));
  });

  test('setTime updates only time', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(reservationDraftProvider.notifier).setTime(time);

    expect(container.read(reservationDraftProvider).time, time);
  });

  test('setHasPreorder toggles the flag', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reservationDraftProvider.notifier);

    notifier.setHasPreorder(true);
    expect(container.read(reservationDraftProvider).hasPreorder, isTrue);

    notifier.setHasPreorder(false);
    expect(container.read(reservationDraftProvider).hasPreorder, isFalse);
  });

  test('setContactName updates both name fields together', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(reservationDraftProvider.notifier).setContactName(
          firstName: 'Ada',
          lastName: 'Yılmaz',
        );

    final draft = container.read(reservationDraftProvider);
    expect(draft.contactFirstName, 'Ada');
    expect(draft.contactLastName, 'Yılmaz');
  });

  test('reset returns the draft to its initial empty state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reservationDraftProvider.notifier);

    notifier.setPartySize(4);
    notifier.setArea(area);
    notifier.setDate(date);
    notifier.setTime(time);
    notifier.setHasPreorder(true);
    notifier.setContactName(firstName: 'Ada', lastName: 'Yılmaz');

    notifier.reset();

    expect(container.read(reservationDraftProvider), const IsEmptyDraft());
  });

  test(
      'setting party size, area, date, time and a valid contact name in '
      'sequence reaches isReadyToReview, mirroring the real step-by-step flow',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reservationDraftProvider.notifier);

    expect(container.read(reservationDraftProvider).isReadyToReview, isFalse);

    notifier.setPartySize(2);
    notifier.setArea(area);
    notifier.setDate(date);
    notifier.setTime(time);
    expect(container.read(reservationDraftProvider).isReadyToReview, isFalse);

    notifier.setContactName(firstName: 'Ada', lastName: 'Yılmaz');
    expect(container.read(reservationDraftProvider).isReadyToReview, isTrue);
  });
}

/// Matches a freshly-built/reset `ReservationDraft` by its own defaults,
/// rather than duplicating each default value inline at every call site.
class IsEmptyDraft extends Matcher {
  const IsEmptyDraft();

  @override
  bool matches(dynamic item, Map matchState) {
    return item.partySize == null &&
        item.area == null &&
        item.date == null &&
        item.time == null &&
        item.hasPreorder == false &&
        item.contactFirstName == '' &&
        item.contactLastName == '';
  }

  @override
  Description describe(Description description) =>
      description.add('an empty/reset ReservationDraft');
}
