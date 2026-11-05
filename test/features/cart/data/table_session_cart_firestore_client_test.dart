import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/data/table_session_cart_firestore_client.dart';

void main() {
  group('deterministicCartLineId', () {
    test(
        'aynı subAccount + aynı customizationsKey her zaman aynı id\'yi üretir',
        () {
      final first = deterministicCartLineId(
        addedBySubAccountId: 'subaccount-ts-1-uid-1',
        customizationsKey: 'prod-1_cheese_none',
      );
      final second = deterministicCartLineId(
        addedBySubAccountId: 'subaccount-ts-1-uid-1',
        customizationsKey: 'prod-1_cheese_none',
      );

      expect(first, second);
    });

    test(
        'aynı customizationsKey ama farklı subAccount farklı id üretir — '
        'iki misafirin ayni urunu eklemesi birbirine karismaz', () {
      final guestA = deterministicCartLineId(
        addedBySubAccountId: 'subaccount-ts-1-guest-a',
        customizationsKey: 'prod-1',
      );
      final guestB = deterministicCartLineId(
        addedBySubAccountId: 'subaccount-ts-1-guest-b',
        customizationsKey: 'prod-1',
      );

      expect(guestA, isNot(guestB));
    });

    test('Firestore doküman id\'sinde geçersiz olan "/" karakteri temizlenir',
        () {
      final id = deterministicCartLineId(
        addedBySubAccountId: 'subaccount-ts-1-uid-1',
        customizationsKey: 'prod-1_not-e: domates/marul',
      );

      expect(id.contains('/'), isFalse);
    });

    test('çok uzun customizationsKey güvenli bir uzunluğa kısaltılır', () {
      final longNote = 'a' * 1000;
      final id = deterministicCartLineId(
        addedBySubAccountId: 'subaccount-ts-1-uid-1',
        customizationsKey: longNote,
      );

      expect(id.length, lessThan(1000));
    });
  });
}
