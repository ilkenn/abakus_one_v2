import 'guest_locale.dart';

/// Hand-written TR/EN strings for the dine-in QR entry/status flow —
/// Self-Order QR Faz 1 (`docs/decisions.md` ADR-054). A small typed class
/// rather than a raw `Map<String, String>` key lookup, per CLAUDE.md's
/// "prefer enums over free strings" spirit: a typo in a string key would
/// silently fall through to nothing at runtime, a typo in a field name is
/// a compile error.
///
/// Deliberately **not** `flutter_localizations`'s ARB/`flutter gen-l10n`
/// pipeline — that generates code, and CLAUDE.md §2 is explicit this
/// project has no code-generation step anywhere. Scope is only the screens
/// that actually use this today (`TableGuestEntryScreen`, status/error
/// messages, `TableContextBadge`) — the rest of the customer app's UI
/// stays Turkish-only, unchanged, exactly as it was before this phase.
class QrFlowStrings {
  const QrFlowStrings._({
    required this.welcomeTitle,
    required this.checkingQr,
    required this.openingTable,
    required this.tableLabel,
    required this.statusNotFound,
    required this.statusInvalid,
    required this.statusExpired,
    required this.statusReserved,
    required this.statusUnknown,
    required this.connectionUnavailable,
    required this.exceptionNotFound,
    required this.exceptionFailedPrecondition,
    required this.exceptionResourceExhausted,
    required this.exceptionUnknown,
    required this.sessionOpenError,
    required this.retryLabel,
    required this.badgeExpiredMessage,
    required this.waiterTooltip,
    required this.billTooltip,
    required this.serviceRequestSent,
    required this.serviceRequestFailedGeneric,
  });

  final String welcomeTitle;
  final String checkingQr;
  final String openingTable;
  final String Function(String tableName) tableLabel;
  final String statusNotFound;
  final String statusInvalid;
  final String statusExpired;
  final String statusReserved;
  final String statusUnknown;
  final String connectionUnavailable;
  final String exceptionNotFound;
  final String exceptionFailedPrecondition;
  final String exceptionResourceExhausted;
  final String exceptionUnknown;
  final String sessionOpenError;
  final String retryLabel;
  final String badgeExpiredMessage;
  final String waiterTooltip;
  final String billTooltip;
  final String serviceRequestSent;
  final String serviceRequestFailedGeneric;

  static const QrFlowStrings tr = QrFlowStrings._(
    welcomeTitle: 'Abaküs Street Food\'a Hoş Geldiniz',
    checkingQr: 'QR kod kontrol ediliyor...',
    openingTable: 'Masa açılıyor...',
    tableLabel: _tableLabelTr,
    statusNotFound: 'Bu QR kod tanınmadı. Lütfen masandaki kodu tekrar okut.',
    statusInvalid:
        'Bu QR kod şu anda geçerli değil. Lütfen masandaki kodu kontrol et '
        'veya bir çalışana bildir.',
    statusExpired: 'Bu QR kodun süresi dolmuş. Lütfen bir çalışana bildir.',
    statusReserved: 'Bu masa rezerve edilmiştir. Lütfen yetkili ile görüşün.',
    statusUnknown: 'Bu QR kod şu anda kullanılamıyor. Lütfen tekrar dene.',
    connectionUnavailable:
        'Şu anda bağlantı kurulamıyor. Lütfen daha sonra tekrar dene.',
    exceptionNotFound:
        'Bu QR kod tanınmadı. Lütfen masandaki kodu tekrar okut.',
    exceptionFailedPrecondition:
        'Bu QR kod şu anda kullanılamıyor. Lütfen bir çalışana bildir.',
    exceptionResourceExhausted:
        'Çok fazla deneme yapıldı. Lütfen biraz bekleyip tekrar dene.',
    exceptionUnknown: 'Masa açılırken bir sorun oluştu. Lütfen tekrar dene.',
    sessionOpenError: 'Masa açılırken bir sorun oluştu. Lütfen tekrar dene.',
    retryLabel: 'Tekrar Dene',
    badgeExpiredMessage: 'Oturum süresi doldu — QR kodu tekrar okutun',
    waiterTooltip: 'Garson Çağır',
    billTooltip: 'Hesap İste',
    serviceRequestSent: 'İsteğiniz iletildi.',
    serviceRequestFailedGeneric: 'İsteğiniz gönderilirken bir sorun oluştu.',
  );

  static const QrFlowStrings en = QrFlowStrings._(
    welcomeTitle: 'Welcome to Abaküs Street Food',
    checkingQr: 'Checking QR code...',
    openingTable: 'Opening your table...',
    tableLabel: _tableLabelEn,
    statusNotFound: 'This QR code was not recognized. Please scan the code '
        'at your table again.',
    statusInvalid: 'This QR code is not currently valid. Please check the '
        'code at your table or let a staff member know.',
    statusExpired: 'This QR code has expired. Please let a staff member '
        'know.',
    statusReserved: 'This table is reserved. Please speak with a staff '
        'member.',
    statusUnknown: 'This QR code is not available right now. Please try '
        'again.',
    connectionUnavailable:
        'Can\'t connect right now. Please try again shortly.',
    exceptionNotFound: 'This QR code was not recognized. Please scan the '
        'code at your table again.',
    exceptionFailedPrecondition: 'This QR code is not available right now. '
        'Please let a staff member know.',
    exceptionResourceExhausted:
        'Too many attempts. Please wait a moment and try again.',
    exceptionUnknown: 'Something went wrong opening your table. Please try '
        'again.',
    sessionOpenError:
        'Something went wrong opening your table. Please try again.',
    retryLabel: 'Try Again',
    badgeExpiredMessage: 'Session expired — please scan the QR code again',
    waiterTooltip: 'Call Waiter',
    billTooltip: 'Request Bill',
    serviceRequestSent: 'Your request has been sent.',
    serviceRequestFailedGeneric: 'Something went wrong sending your request.',
  );

  static QrFlowStrings of(GuestLocale locale) => switch (locale) {
        GuestLocale.tr => tr,
        GuestLocale.en => en,
      };

  static String _tableLabelTr(String tableName) => 'Masa: $tableName';
  static String _tableLabelEn(String tableName) => 'Table: $tableName';
}
