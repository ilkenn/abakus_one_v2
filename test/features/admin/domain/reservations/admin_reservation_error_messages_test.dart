import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/admin_reservation_gateway.dart';
import 'package:abakus_one_v2/features/admin/domain/reservations/admin_reservation_error_messages.dart';

void main() {
  test(
      'unauthenticated and permission-denied both map to a generic authorization message',
      () {
    expect(
      adminReservationErrorMessage(
          const AdminReservationException('unauthenticated', '')),
      'Bu işlem için yetkiniz yok.',
    );
    expect(
      adminReservationErrorMessage(
          const AdminReservationException('permission-denied', '')),
      'Bu işlem için yetkiniz yok.',
    );
  });

  test('not-found maps to a record-not-found message', () {
    expect(
      adminReservationErrorMessage(
          const AdminReservationException('not-found', '')),
      'Kayıt bulunamadı. Sayfayı yenileyip tekrar deneyin.',
    );
  });

  test('invalid-argument maps to a generic input-problem message', () {
    expect(
      adminReservationErrorMessage(
          const AdminReservationException('invalid-argument', '')),
      'Girilen bilgilerde bir sorun var. Lütfen kontrol edin.',
    );
  });

  test('resource-exhausted maps to a capacity-limit message', () {
    expect(
      adminReservationErrorMessage(
          const AdminReservationException('resource-exhausted', '')),
      'Bu işlem şu anda gerçekleştirilemiyor (kapasite sınırı). Lütfen daha sonra tekrar deneyin.',
    );
  });

  group('failed-precondition — message-text-sensitive branches', () {
    test('table already booked', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'This table is already booked for an overlapping time.',
        )),
        'Bu masa seçilen saat için zaten dolu.',
      );
    });

    test('table not active', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'This table is not currently active.',
        )),
        'Bu masa şu anda aktif değil.',
      );
    });

    test('table wrong area', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'This table does not belong to the reservation\'s confirmed area.',
        )),
        'Bu masa, rezervasyonun onaylı alanına ait değil.',
      );
    });

    test('table context currently open blocks reassignment', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'This reservation\'s table context is currently open — close it before reassigning.',
        )),
        'Önce rezervasyon masasını kapatın.',
      );
    });

    test('outside operating hours', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          "requestedTime is outside this branch's operating hours.",
        )),
        'Seçilen saat şubenin çalışma saatleri dışında.',
      );
    });

    test('already terminal (Faz R.3B)', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'Reservation is already terminal (status: completed) and cannot be cancelled.',
        )),
        'Bu rezervasyon zaten sonuçlanmış durumda.',
      );
    });

    test('complete before confirmedTime (Faz R.3B)', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'A reservation cannot be marked completed before its confirmedTime.',
        )),
        'Rezervasyon saati gelmeden "Tamamlandı" olarak işaretlenemez.',
      );
    });

    test('no-show before confirmedTime (Faz R.3B)', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'A reservation cannot be marked no-show before its confirmedTime.',
        )),
        'Rezervasyon saati gelmeden "Gelmedi" olarak işaretlenemez.',
      );
    });

    test('complete requires confirmed status (Faz R.3B)', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'Only a confirmed reservation may be marked completed (current status: rejected).',
        )),
        'Yalnızca onaylanmış bir rezervasyon tamamlandı olarak işaretlenebilir.',
      );
    });

    test('no-show requires confirmed status (Faz R.3B)', () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'Only a confirmed reservation may be marked no-show (current status: rejected).',
        )),
        'Yalnızca onaylanmış bir rezervasyon gelmedi olarak işaretlenebilir.',
      );
    });

    test(
        'unrecognized failed-precondition text falls back to a generic message',
        () {
      expect(
        adminReservationErrorMessage(const AdminReservationException(
          'failed-precondition',
          'something unexpected happened',
        )),
        'Bu işlem şu anki durumla gerçekleştirilemiyor.',
      );
    });
  });

  test('any unrecognized error code falls back to a generic message', () {
    expect(
      adminReservationErrorMessage(
          const AdminReservationException('internal', 'boom')),
      'Bir şeyler ters gitti. Lütfen tekrar deneyin.',
    );
  });

  test('the raw backend message text is never returned to the caller', () {
    const rawMessage =
        'Internal: transaction aborted at document ref /reservations/abc123';
    final mapped = adminReservationErrorMessage(
      const AdminReservationException('internal', rawMessage),
    );
    expect(mapped, isNot(contains('transaction')));
    expect(mapped, isNot(contains('abc123')));
  });
}
