import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/widgets/loyalty_history_tile.dart';

void main() {
  group('loyaltyHistoryEntryTitle', () {
    test('every closed entry type has a distinct, non-empty Turkish label', () {
      final labels =
          LoyaltyLedgerEntryType.values.map(loyaltyHistoryEntryTitle).toSet();
      expect(labels, hasLength(LoyaltyLedgerEntryType.values.length));
      for (final label in labels) {
        expect(label, isNotEmpty);
      }
    });

    test('orderEarn — the only entry type real data can contain today', () {
      expect(
        loyaltyHistoryEntryTitle(LoyaltyLedgerEntryType.orderEarn),
        'Siparişten Boncuk kazandın',
      );
    });
  });

  group('loyaltyHistoryEntrySubtitle', () {
    test('no debt applied — no subtitle', () {
      final entry = LoyaltyHistoryEntry(
        eventId: 'e1',
        type: LoyaltyLedgerEntryType.orderEarn,
        displayBoncukDelta: 10,
        debtAppliedBoncuk: 0,
        occurredAt: DateTime(2026, 8, 23),
        orderId: null,
      );
      expect(loyaltyHistoryEntrySubtitle(entry), isNull);
    });

    test(
        'debt applied — a calm, non-jargon explanation, never raw accounting field names',
        () {
      final entry = LoyaltyHistoryEntry(
        eventId: 'e1',
        type: LoyaltyLedgerEntryType.orderEarn,
        displayBoncukDelta: 5,
        debtAppliedBoncuk: 5,
        occurredAt: DateTime(2026, 8, 23),
        orderId: null,
      );
      final subtitle = loyaltyHistoryEntrySubtitle(entry);
      expect(subtitle, '5 Boncuk önceki iade bakiyene uygulandı');
      expect(subtitle, isNot(contains('debt')));
      expect(subtitle, isNot(contains('entitlement')));
    });
  });

  group('formatLoyaltyHistoryDate', () {
    test(
        'formats as DD.MM.YYYY, matching this app\'s established date convention',
        () {
      expect(formatLoyaltyHistoryDate(DateTime(2026, 8, 23)), '23.08.2026');
    });
  });

  group('loyaltyLedgerEntryTypeFromWire', () {
    test('recognizes every closed backend type', () {
      for (final type in LoyaltyLedgerEntryType.values) {
        if (type == LoyaltyLedgerEntryType.unknown) continue;
        expect(loyaltyLedgerEntryTypeFromWire(type.name), type);
      }
    });

    test('an unrecognized wire value maps to unknown, never crashes', () {
      expect(
        loyaltyLedgerEntryTypeFromWire('somethingFromTheFuture'),
        LoyaltyLedgerEntryType.unknown,
      );
    });
  });
}
