import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_qr_resolution.dart';

void main() {
  test('TableQrValidityStatus beklenen tum durumlari icerir', () {
    expect(TableQrValidityStatus.values, [
      TableQrValidityStatus.valid,
      TableQrValidityStatus.invalid,
      TableQrValidityStatus.expired,
      TableQrValidityStatus.notFound,
    ]);
  });

  group('isUsable', () {
    test('valid sonuc kullanilabilir', () {
      final result = TableQrResolutionResult.valid(
        restaurantId: 'restaurant_1',
        branchId: 'branch_1',
        tableId: 'table_1',
        tableDisplayName: 'Masa 1',
        branchDisplayName: 'Kadıköy Şube',
        supportedLanguageCodes: const ['tr', 'en'],
      );

      expect(result.isUsable, isTrue);
      expect(result.restaurantId, 'restaurant_1');
      expect(result.tableDisplayName, 'Masa 1');
      expect(result.supportedLanguageCodes, ['tr', 'en']);
    });

    test('notFound sonucu kullanilamaz ve kimlik bilgisi tasimaz', () {
      final result = TableQrResolutionResult.notFound();

      expect(result.isUsable, isFalse);
      expect(result.validityStatus, TableQrValidityStatus.notFound);
      expect(result.restaurantId, isNull);
      expect(result.branchId, isNull);
      expect(result.tableId, isNull);
    });

    test('invalid sonucu kullanilamaz', () {
      final result = TableQrResolutionResult.invalid();

      expect(result.isUsable, isFalse);
      expect(result.validityStatus, TableQrValidityStatus.invalid);
    });

    test('expired sonucu kullanilamaz', () {
      final result = TableQrResolutionResult.expired();

      expect(result.isUsable, isFalse);
      expect(result.validityStatus, TableQrValidityStatus.expired);
    });
  });
}
