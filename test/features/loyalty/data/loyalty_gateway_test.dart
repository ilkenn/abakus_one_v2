import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';

/// P3A (2026-08-23) — pure parser tests for the loyalty gateway's response
/// contracts, mirroring `customer_registration_gateway_test.dart`'s own
/// "never assume a wire value's Dart runtime type" discipline.
void main() {
  group('parseLoyaltySnapshot', () {
    Map<String, dynamic> wellFormedResponse({
      Map<String, dynamic>? policy,
    }) =>
        {
          'spendableBalance': 10,
          'boncukDebt': 0,
          'earningRemainderMinorUnits': 4900,
          'minorUnitsUntilNextBoncuk': 100,
          'lifetimeEarned': 10,
          'lifetimeRedeemed': 0,
          'policy': policy ??
              {
                'earningSpendMinorUnits': 5000,
                'earningBoncukAmount': 5,
                'redemptionValueMinorUnitsPerBoncuk': 100,
                'maxRedemptionBasisPoints': 5000,
              },
        };

    test('parses a well-formed response, including the nested policy object',
        () {
      final snapshot = parseLoyaltySnapshot(wellFormedResponse());
      expect(snapshot.spendableBalance, 10);
      expect(snapshot.boncukDebt, 0);
      expect(snapshot.earningRemainderMinorUnits, 4900);
      expect(snapshot.minorUnitsUntilNextBoncuk, 100);
      expect(snapshot.lifetimeEarned, 10);
      expect(snapshot.lifetimeRedeemed, 0);
      expect(snapshot.earningSpendMinorUnits, 5000);
      expect(snapshot.earningBoncukAmount, 5);
      expect(snapshot.redemptionValueMinorUnitsPerBoncuk, 100);
      expect(snapshot.maxRedemptionBasisPoints, 5000);
    });

    test(
        'a different (non-default), non-integer-reducible policy is parsed verbatim — proves the policy is genuinely read from the wire, not hardcoded or client-derived',
        () {
      final snapshot = parseLoyaltySnapshot(wellFormedResponse(
        policy: {
          'earningSpendMinorUnits': 5000,
          'earningBoncukAmount': 3,
          'redemptionValueMinorUnitsPerBoncuk': 50,
          'maxRedemptionBasisPoints': 2500,
        },
      )
        ..['earningRemainderMinorUnits'] = 33
        ..['minorUnitsUntilNextBoncuk'] = 1634);
      expect(snapshot.earningSpendMinorUnits, 5000);
      expect(snapshot.earningBoncukAmount, 3);
      expect(snapshot.earningRemainderMinorUnits, 33);
      expect(snapshot.minorUnitsUntilNextBoncuk, 1634);
      expect(snapshot.redemptionValueMinorUnitsPerBoncuk, 50);
      expect(snapshot.maxRedemptionBasisPoints, 2500);
    });

    test('a missing field throws FormatException, never defaults silently', () {
      expect(
        () => parseLoyaltySnapshot({'spendableBalance': 10}),
        throwsA(isA<FormatException>()),
      );
    });

    test(
        'a missing minorUnitsUntilNextBoncuk throws FormatException, never re-derived client-side',
        () {
      final response = wellFormedResponse()
        ..remove('minorUnitsUntilNextBoncuk');
      expect(
        () => parseLoyaltySnapshot(response),
        throwsA(isA<FormatException>()),
      );
    });

    test('a non-numeric field throws FormatException', () {
      final response = wellFormedResponse()..['spendableBalance'] = 'ten';
      expect(
        () => parseLoyaltySnapshot(response),
        throwsA(isA<FormatException>()),
      );
    });

    test(
        'a missing policy object throws FormatException, never defaults silently',
        () {
      final response = wellFormedResponse()..remove('policy');
      expect(
        () => parseLoyaltySnapshot(response),
        throwsA(isA<FormatException>()),
      );
    });

    test('a policy with a missing/non-numeric field throws FormatException',
        () {
      final response = wellFormedResponse(policy: {
        'earningSpendMinorUnits': 5000,
        'earningBoncukAmount': 5,
        'redemptionValueMinorUnitsPerBoncuk': 100,
        // maxRedemptionBasisPoints deliberately missing.
      });
      expect(
        () => parseLoyaltySnapshot(response),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('parseLoyaltyHistoryPage', () {
    test('parses an empty page', () {
      final page = parseLoyaltyHistoryPage({'rows': [], 'nextCursor': null});
      expect(page.entries, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test('parses a page with rows and a next cursor', () {
      final page = parseLoyaltyHistoryPage({
        'rows': [
          {
            'eventId': 'entry-1',
            'type': 'orderEarn',
            'displayBoncukDelta': 10,
            'debtAppliedBoncuk': 0,
            'occurredAt': '2026-08-23T10:00:00.000Z',
            'orderId': 'order-1',
          },
        ],
        'nextCursor': '2026-08-23T10:00:00.000Z',
      });
      expect(page.entries, hasLength(1));
      expect(page.entries.single.type, LoyaltyLedgerEntryType.orderEarn);
      expect(page.entries.single.displayBoncukDelta, 10);
      expect(page.entries.single.orderId, 'order-1');
      expect(page.nextCursor, '2026-08-23T10:00:00.000Z');
    });

    test('an unrecognized type string maps to unknown, never throws', () {
      final page = parseLoyaltyHistoryPage({
        'rows': [
          {
            'eventId': 'entry-2',
            'type': 'somethingFromANewerBackend',
            'displayBoncukDelta': 1,
            'debtAppliedBoncuk': 0,
            'occurredAt': '2026-08-23T10:00:00.000Z',
            'orderId': null,
          },
        ],
        'nextCursor': null,
      });
      expect(page.entries.single.type, LoyaltyLedgerEntryType.unknown);
    });

    test('an invalid occurredAt throws FormatException, never defaults to now',
        () {
      expect(
        () => parseLoyaltyHistoryPage({
          'rows': [
            {
              'eventId': 'entry-3',
              'type': 'orderEarn',
              'displayBoncukDelta': 1,
              'debtAppliedBoncuk': 0,
              'occurredAt': 'not-a-date',
              'orderId': null,
            },
          ],
          'nextCursor': null,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rows must be a list, never coerced from another shape', () {
      expect(
        () =>
            parseLoyaltyHistoryPage({'rows': 'not-a-list', 'nextCursor': null}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
