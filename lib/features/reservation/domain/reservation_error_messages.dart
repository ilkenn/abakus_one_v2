import '../data/reservation_gateway.dart';

/// Translates a [ReservationException] (mirrors the backend's own
/// `HttpsError` code + message) into a customer-safe Turkish message —
/// Faz R.2 §21. The raw Firebase error code/message is never shown to the
/// user.
String reservationErrorMessage(ReservationException error) {
  final message = error.message.toLowerCase();

  switch (error.code) {
    case 'unauthenticated':
    case 'permission-denied':
      return 'Rezervasyon için telefon numaranızla giriş yapmanız gerekiyor.';
    case 'not-found':
      return 'Seçtiğiniz şube veya alan bulunamadı. Lütfen tekrar deneyin.';
    case 'invalid-argument':
      return 'Girdiğiniz bilgilerde bir sorun var. Lütfen tekrar kontrol edin.';
    case 'failed-precondition':
      if (message.contains('minutes from now') || message.contains('advance')) {
        return 'Rezervasyonlar en az 30 dakika sonrası için oluşturulabilir.';
      }
      if (message.contains('booking horizon')) {
        return 'Seçtiğiniz tarih çok ileride. Lütfen daha yakın bir tarih seçin.';
      }
      if (message.contains('operating hours')) {
        return 'Seçtiğiniz saat için şube rezervasyona kapalı. Lütfen başka bir saat seçin.';
      }
      if (message.contains('area') && message.contains('not currently')) {
        return 'Seçtiğiniz alan şu anda rezervasyona uygun değil.';
      }
      if (message.contains('branch') && message.contains('not currently')) {
        return 'Bu şube şu anda rezervasyon kabul etmiyor.';
      }
      if (message.contains('already used')) {
        return 'Bu talep zaten gönderildi. Lütfen sayfayı yenileyin.';
      }
      if (message.contains('expired')) {
        return 'Bu öneri için yanıt süresi doldu.';
      }
      // Faz R.3B §5 — LOCKED copy: the customer cancellation cutoff has
      // been reached, server clock only.
      if (message.contains('customercancellationcutoffreached')) {
        return 'Rezervasyon saatiniz yaklaştığı için uygulamadan iptal edilemiyor. '
            'Lütfen restoranla iletişime geçin.';
      }
      // Faz R.3B §6 — LOCKED copy: the linked preorder has already reached
      // the kitchen, so the customer cannot self-cancel from the app.
      if (message.contains('reservationpreorderreleasedtokitchen')) {
        return 'Ön siparişiniz mutfağa iletildiği için rezervasyonunuzu '
            'uygulamadan iptal edemezsiniz. Lütfen restoranla iletişime geçin.';
      }
      if (message.contains('already terminal')) {
        return 'Bu rezervasyon zaten sonuçlanmış durumda.';
      }
      // Includes the capacity-race case ("no concrete threshold to invent
      // beyond what the backend actually returns" — Faz R.2 §21's own
      // instruction not to guess at a message the backend text doesn't
      // support) — the generic fallback below already reads naturally for
      // "bu saat az önce doldu" style races the backend doesn't further
      // categorize.
      return 'Bu saat için az önce bir değişiklik oldu. Lütfen tekrar deneyin.';
    default:
      return 'Bir şeyler ters gitti. Lütfen tekrar deneyin.';
  }
}
