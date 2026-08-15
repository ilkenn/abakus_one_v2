import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/reservation/data/reservation_gateway.dart';
import 'package:abakus_one_v2/features/reservation/domain/reservation_error_messages.dart';

void main() {
  test('unauthenticated and permission-denied both ask for phone login', () {
    expect(
      reservationErrorMessage(
          const ReservationException('unauthenticated', '')),
      'Rezervasyon için telefon numaranızla giriş yapmanız gerekiyor.',
    );
    expect(
      reservationErrorMessage(
          const ReservationException('permission-denied', '')),
      'Rezervasyon için telefon numaranızla giriş yapmanız gerekiyor.',
    );
  });

  test('not-found maps to a branch/area-not-found message', () {
    expect(
      reservationErrorMessage(const ReservationException('not-found', '')),
      'Seçtiğiniz şube veya alan bulunamadı. Lütfen tekrar deneyin.',
    );
  });

  test('invalid-argument maps to a generic input-problem message', () {
    expect(
      reservationErrorMessage(
          const ReservationException('invalid-argument', '')),
      'Girdiğiniz bilgilerde bir sorun var. Lütfen tekrar kontrol edin.',
    );
  });

  group('failed-precondition — message-text-sensitive branches', () {
    test('minimum-advance violation', () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'requestedTime must be at least 30 minutes from now',
        )),
        'Rezervasyonlar en az 30 dakika sonrası için oluşturulabilir.',
      );
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'not enough advance notice given',
        )),
        'Rezervasyonlar en az 30 dakika sonrası için oluşturulabilir.',
      );
    });

    test('booking horizon violation', () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'requestedTime is beyond the booking horizon',
        )),
        'Seçtiğiniz tarih çok ileride. Lütfen daha yakın bir tarih seçin.',
      );
    });

    test('outside operating hours', () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          "requestedTime is outside this branch's operating hours.",
        )),
        'Seçtiğiniz saat için şube rezervasyona kapalı. Lütfen başka bir saat seçin.',
      );
    });

    test('area not currently accepting reservations', () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'This area is not currently accepting reservations',
        )),
        'Seçtiğiniz alan şu anda rezervasyona uygun değil.',
      );
    });

    test('branch not currently accepting reservations', () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'This branch is not currently accepting reservations',
        )),
        'Bu şube şu anda rezervasyon kabul etmiyor.',
      );
    });

    test('idempotency key already used', () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'This submissionKey has already used',
        )),
        'Bu talep zaten gönderildi. Lütfen sayfayı yenileyin.',
      );
    });

    test('proposal response window expired', () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'This proposal has expired',
        )),
        'Bu öneri için yanıt süresi doldu.',
      );
    });

    test('Faz R.3B §5 — customer cancellation cutoff reached, LOCKED copy', () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'customerCancellationCutoffReached',
        )),
        'Rezervasyon saatiniz yaklaştığı için uygulamadan iptal edilemiyor. '
        'Lütfen restoranla iletişime geçin.',
      );
    });

    test(
        'Faz R.3B §6 — released preorder blocks self-cancellation, LOCKED copy',
        () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'reservationPreorderReleasedToKitchen',
        )),
        'Ön siparişiniz mutfağa iletildiği için rezervasyonunuzu '
        'uygulamadan iptal edemezsiniz. Lütfen restoranla iletişime geçin.',
      );
    });

    test('Faz R.3B — already-terminal reservation cannot be cancelled again',
        () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'Reservation is already terminal (status: completed) and cannot be cancelled.',
        )),
        'Bu rezervasyon zaten sonuçlanmış durumda.',
      );
    });

    test(
        'unrecognized failed-precondition text falls back to a generic '
        'capacity-race message rather than inventing a specific one', () {
      expect(
        reservationErrorMessage(const ReservationException(
          'failed-precondition',
          'slot is no longer available',
        )),
        'Bu saat için az önce bir değişiklik oldu. Lütfen tekrar deneyin.',
      );
    });
  });

  test('any unrecognized error code falls back to a generic message', () {
    expect(
      reservationErrorMessage(const ReservationException('internal', 'boom')),
      'Bir şeyler ters gitti. Lütfen tekrar deneyin.',
    );
    expect(
      reservationErrorMessage(
          const ReservationException('deadline-exceeded', '')),
      'Bir şeyler ters gitti. Lütfen tekrar deneyin.',
    );
  });

  test('the raw backend message text is never returned to the caller', () {
    const rawMessage =
        'Internal: transaction aborted at document ref /reservations/abc123';
    final mapped = reservationErrorMessage(
      const ReservationException('internal', rawMessage),
    );
    expect(mapped, isNot(contains('transaction')));
    expect(mapped, isNot(contains('abc123')));
  });
}
