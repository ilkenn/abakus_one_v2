import '../data/reservation_gateway.dart';

/// Translates a [ReservationException] (mirrors the backend's own
/// `HttpsError` code + message) into a customer-safe Turkish message —
/// Faz R.2 §21. The raw Firebase error code/message is never shown to the
/// user.
String reservationErrorMessage(ReservationException error) {
  // Boncuk Loyalty P6-B (2026-08-24) — a Boncuk-specific rejection is
  // mapped from [ReservationException.boncukErrorReason] (the SAME stable,
  // machine-readable server reason vocabulary
  // `takeaway_checkout_screen.dart`/`delivery_checkout_screen.dart` branch
  // on), NEVER inferred from [error.code] alone: `invalid-argument`/
  // `failed-precondition` are also used for entirely unrelated reservation
  // validation in this same callable.
  final boncukReason = error.boncukErrorReason;
  if (boncukReason != null) {
    switch (boncukReason) {
      case 'boncuk/exceeds-max-usable':
        return 'Boncuk bakiyeniz veya kullanabileceğiniz miktar değişti. '
            'Bilgileri güncelledik; tekrar seçim yapın.';
      case 'boncuk/account-unavailable':
        return 'Boncuk hesabınıza şu anda ulaşılamıyor. Tekrar deneyebilir '
            'veya Boncuk kullanmadan devam edebilirsiniz.';
      case 'boncuk/policy-unavailable':
        return 'Boncuk kullanımı şu anda geçici olarak kullanılamıyor. '
            'Biraz sonra tekrar deneyebilirsiniz.';
      // Boncuk Loyalty P7-D (2026-08-24) — catalog-reward-specific reasons,
      // same shared `boncukErrorReason` field/namespace.
      case 'catalogReward/reward-not-found':
      case 'catalogReward/reward-not-currently-valid':
        return 'Seçtiğiniz ödül artık kullanılamıyor. Lütfen tekrar seçim '
            'yapın veya ödül kullanmadan devam edin.';
      case 'catalogReward/product-not-in-cart':
        return 'Seçtiğiniz ödül için uygun bir ürün ön siparişinizde '
            'bulunamadı. Lütfen ön siparişinizi kontrol edin.';
      case 'catalogReward/insufficient-balance':
        return 'Bu ödül için yeterli Boncuk bakiyeniz yok. Bilgileri '
            'güncelledik; ödül kullanmadan devam edebilirsiniz.';
      case 'catalogReward/account-unavailable':
        return 'Boncuk hesabınıza şu anda ulaşılamıyor. Tekrar deneyebilir '
            'veya ödül kullanmadan devam edebilirsiniz.';
      case 'catalogReward/benefit-stacking-not-allowed':
      case 'benefit/stacking-not-allowed':
        return 'Aynı anda birden fazla avantaj kullanılamaz. Lütfen '
            'birini seçin.';
      case 'catalogReward/channel-not-eligible':
        return 'Seçtiğiniz ödül Rezervasyon Ön Sipariş için kullanılamıyor. '
            'Lütfen tekrar seçim yapın veya ödül kullanmadan devam edin.';
      // Server-Authoritative Campaign Engine P8-C.2 (2026-08-25) —
      // campaign-specific reasons, same shared `boncukErrorReason`
      // field/namespace. Mirrors `delivery_checkout_screen.dart`'s own
      // copy, adapted to this screen's formal tense.
      case 'campaign/not-found':
        return 'Seçtiğiniz kampanya artık bulunamıyor. Lütfen tekrar seçim '
            'yapın veya kampanya kullanmadan devam edin.';
      case 'campaign/inactive':
      case 'campaign/archived':
        return 'Seçtiğiniz kampanya artık geçerli değil. Lütfen tekrar '
            'seçim yapın veya kampanya kullanmadan devam edin.';
      case 'campaign/channel-not-eligible':
        return 'Seçtiğiniz kampanya Rezervasyon Ön Sipariş için geçerli '
            'değil.';
      case 'campaign/schedule-not-open':
        return 'Seçtiğiniz kampanya şu anda geçerli saatlerde değil.';
      case 'campaign/minimum-basket-not-met':
        return 'Bu kampanya için ön sipariş tutarınız yeterli değil.';
      case 'campaign/no-eligible-line':
      case 'campaign/trigger-quantity-not-met':
        return 'Ön siparişinizde bu kampanyaya uygun bir ürün yok.';
      case 'campaign/usage-limit-reached':
      case 'campaign/customer-usage-limit-reached':
        return 'Bu kampanyanın kullanım hakkı doldu.';
      case 'campaign/reservation-conflict':
        return 'Kampanya şu anda kullanılamıyor. Lütfen tekrar deneyin.';
      default:
        return 'Boncuk kullanılırken bir sorun oluştu. Boncuk kullanmadan '
            'devam edebilirsiniz.';
    }
  }

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
