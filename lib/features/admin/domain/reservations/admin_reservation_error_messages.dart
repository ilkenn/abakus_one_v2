import '../../data/admin_reservation_gateway.dart';

/// Translates an [AdminReservationException] into operational, staff-
/// facing Turkish copy — Faz R.3A §14. Deliberately separate from
/// `reservationErrorMessage` (customer-facing): the audience, tone, and
/// the specific backend error strings each maps are different — a staff
/// member sees "why the operation failed," not "why your booking didn't
/// go through." The raw backend message is never shown to a user.
String adminReservationErrorMessage(AdminReservationException error) {
  final message = error.message.toLowerCase();

  switch (error.code) {
    case 'unauthenticated':
    case 'permission-denied':
      return 'Bu işlem için yetkiniz yok.';
    case 'not-found':
      return 'Kayıt bulunamadı. Sayfayı yenileyip tekrar deneyin.';
    case 'invalid-argument':
      return 'Girilen bilgilerde bir sorun var. Lütfen kontrol edin.';
    case 'resource-exhausted':
      return 'Bu işlem şu anda gerçekleştirilemiyor (kapasite sınırı). Lütfen daha sonra tekrar deneyin.';
    case 'failed-precondition':
      if (message.contains('already booked') ||
          message.contains('overlapping')) {
        return 'Bu masa seçilen saat için zaten dolu.';
      }
      if (message.contains('not currently active')) {
        return 'Bu masa şu anda aktif değil.';
      }
      if (message.contains('does not belong to the reservation')) {
        return 'Bu masa, rezervasyonun onaylı alanına ait değil.';
      }
      if (message.contains('table context is currently open')) {
        return 'Önce rezervasyon masasını kapatın.';
      }
      if (message.contains('outside this branch\'s operating hours') ||
          message.contains('outside this branch')) {
        return 'Seçilen saat şubenin çalışma saatleri dışında.';
      }
      if (message.contains('already has at least one membership')) {
        return 'Bu organizasyon için ilk yönetici hesabı zaten oluşturulmuş.';
      }
      if (message.contains('archived')) {
        return 'Bu hesap arşivlenmiş — durumu artık değiştirilemez.';
      }
      // Faz R.3B — terminal-action guards. Checked BEFORE the older, more
      // general 'confirmed reservation' substring check below — every one
      // of these messages also happens to contain that same substring
      // ("Only a confirmed reservation may be marked completed..."), so
      // ordering here is load-bearing, not cosmetic.
      if (message.contains('already terminal')) {
        return 'Bu rezervasyon zaten sonuçlanmış durumda.';
      }
      if (message
          .contains('cannot be marked completed before its confirmedtime')) {
        return 'Rezervasyon saati gelmeden "Tamamlandı" olarak işaretlenemez.';
      }
      if (message
          .contains('cannot be marked no-show before its confirmedtime')) {
        return 'Rezervasyon saati gelmeden "Gelmedi" olarak işaretlenemez.';
      }
      if (message
          .contains('only a confirmed reservation may be marked completed')) {
        return 'Yalnızca onaylanmış bir rezervasyon tamamlandı olarak işaretlenebilir.';
      }
      if (message
          .contains('only a confirmed reservation may be marked no-show')) {
        return 'Yalnızca onaylanmış bir rezervasyon gelmedi olarak işaretlenebilir.';
      }
      if (message.contains('confirmed reservation')) {
        return 'Masa yalnızca onaylanmış bir rezervasyona atanabilir.';
      }
      if (message.contains('no assigned table')) {
        return 'Bu rezervasyona henüz bir masa atanmadı.';
      }
      return 'Bu işlem şu anki durumla gerçekleştirilemiyor.';
    default:
      return 'Bir şeyler ters gitti. Lütfen tekrar deneyin.';
  }
}
