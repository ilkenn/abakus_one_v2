import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_qr_code.dart';

TableQrCode buildQrCode({
  TableQrStatus status = TableQrStatus.active,
  DateTime? expiresAt,
}) {
  return TableQrCode(
    id: 'qr_1',
    tableId: 'table_1',
    branchId: 'branch_1',
    opaqueToken: 'a1b2c3d4e5f6',
    status: status,
    createdAt: DateTime(2026, 1, 1),
    activatedAt: DateTime(2026, 1, 1),
    expiresAt: expiresAt,
  );
}

void main() {
  test('TableQrStatus beklenen tum durumlari icerir', () {
    expect(TableQrStatus.values, [
      TableQrStatus.active,
      TableQrStatus.inactive,
      TableQrStatus.rotated,
      TableQrStatus.expired,
    ]);
  });

  group('TableQrCode.isValidAt', () {
    final now = DateTime(2026, 6, 1);

    test('active ve suresiz ise gecerlidir', () {
      final code = buildQrCode(status: TableQrStatus.active);
      expect(code.isValidAt(now), isTrue);
    });

    test('inactive ise gecersizdir', () {
      final code = buildQrCode(status: TableQrStatus.inactive);
      expect(code.isValidAt(now), isFalse);
    });

    test('rotated ise gecersizdir (eski QR yeni oturum acamaz)', () {
      final code = buildQrCode(status: TableQrStatus.rotated);
      expect(code.isValidAt(now), isFalse);
    });

    test('status active olsa bile expiresAt gecmisse gecersizdir', () {
      final code = buildQrCode(
        status: TableQrStatus.active,
        expiresAt: DateTime(2026, 1, 15),
      );
      expect(code.isValidAt(now), isFalse);
    });

    test('expiresAt henuz gelmemisse gecerlidir', () {
      final code = buildQrCode(
        status: TableQrStatus.active,
        expiresAt: DateTime(2026, 12, 31),
      );
      expect(code.isValidAt(now), isTrue);
    });
  });

  test('rotasyon zinciri previousQrCodeId ile izlenebilir', () {
    final oldCode = buildQrCode(status: TableQrStatus.active);
    final rotatedOld = oldCode.copyWith(
      status: TableQrStatus.rotated,
      rotatedAt: DateTime(2026, 6, 1),
    );
    final newCode = TableQrCode(
      id: 'qr_2',
      tableId: oldCode.tableId,
      branchId: oldCode.branchId,
      opaqueToken: 'f6e5d4c3b2a1',
      status: TableQrStatus.active,
      createdAt: DateTime(2026, 6, 1),
      previousQrCodeId: oldCode.id,
    );

    expect(rotatedOld.isValidAt(DateTime(2026, 6, 2)), isFalse);
    expect(newCode.isValidAt(DateTime(2026, 6, 2)), isTrue);
    expect(newCode.previousQrCodeId, oldCode.id);
  });
}
