import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/utils/clock.dart';
import 'package:abakus_one_v2/features/qr/application/use_cases/resolve_table_qr_token.dart';
import 'package:abakus_one_v2/features/qr/data/dev_table_qr_seed.dart';
import 'package:abakus_one_v2/features/qr/data/table_qr_code_repository.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_qr_resolution.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_table_repository.dart';

class _FixedClock implements Clock {
  _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

void main() {
  late InMemoryTableQrCodeRepository qrCodeRepository;
  late InMemoryRestaurantTableRepository tableRepository;
  late ResolveTableQrToken resolve;

  setUp(() {
    // Anchored to the same fixed instant DevTableQrSeed.seed() computes
    // expiredToken's expiresAt from and ResolveTableQrToken resolves
    // against — deterministic regardless of real wall-clock time at
    // test-run time (see DevTableQrSeed.seed's `now` doc comment).
    final fixedNow = DateTime(2026, 8, 9, 12);
    qrCodeRepository = InMemoryTableQrCodeRepository();
    tableRepository = InMemoryRestaurantTableRepository();
    DevTableQrSeed.seed(
      tableRepository: tableRepository,
      qrCodeRepository: qrCodeRepository,
      now: fixedNow,
    );
    resolve = ResolveTableQrToken(
      clock: _FixedClock(fixedNow),
      qrCodeRepository: qrCodeRepository,
      tableRepository: tableRepository,
    );
  });

  test('gecerli token dogru masaya cozumlenir', () async {
    final result = await resolve.call(DevTableQrSeed.validTokenTable12);

    expect(result.validityStatus, TableQrValidityStatus.valid);
    expect(result.isUsable, isTrue);
    expect(result.tableId, DevTableQrSeed.table12Id);
    expect(result.tableDisplayName, 'Masa 12');
    expect(result.branchId, DevTableQrSeed.branchId);
    expect(result.restaurantId, isNotNull);
    expect(result.branchDisplayName, isNotNull);
  });

  test('ikinci gecerli token farkli bir masaya cozumlenir', () async {
    final result = await resolve.call(DevTableQrSeed.validTokenTable7);

    expect(result.validityStatus, TableQrValidityStatus.valid);
    expect(result.tableId, DevTableQrSeed.table7Id);
    expect(result.tableDisplayName, 'Masa 7');
  });

  test('bilinmeyen token notFound doner', () async {
    final result = await resolve.call('BILINMEYEN-TOKEN-XYZ');

    expect(result.validityStatus, TableQrValidityStatus.notFound);
    expect(result.isUsable, isFalse);
    expect(result.tableId, isNull);
  });

  test('suresi dolmus token expired doner', () async {
    final result = await resolve.call(DevTableQrSeed.expiredToken);

    expect(result.validityStatus, TableQrValidityStatus.expired);
    expect(result.isUsable, isFalse);
  });

  test('rotasyonla degistirilmis token invalid doner', () async {
    final result = await resolve.call(DevTableQrSeed.rotatedToken);

    expect(result.validityStatus, TableQrValidityStatus.invalid);
    expect(result.isUsable, isFalse);
  });

  test('bos string token notFound doner', () async {
    final result = await resolve.call('');

    expect(result.validityStatus, TableQrValidityStatus.notFound);
  });
}
