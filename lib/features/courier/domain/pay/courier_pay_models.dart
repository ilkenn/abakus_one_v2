/// ADR-085 stage 5 — courier pay, shifts and earnings as the server
/// (`functions/src/courierPay.ts`) returns them. Amounts are integer kuruş;
/// dates are Europe/Istanbul calendar days (`YYYY-MM-DD`).
library;

/// Shop couriers are paid by the hour and per package; pool couriers per
/// package only.
enum CourierPayKind {
  shop,
  pool;

  String get label => switch (this) {
        CourierPayKind.shop => 'Dükkan Kuryesi',
        CourierPayKind.pool => 'Havuz Kuryesi',
      };

  static CourierPayKind parse(Object? raw) =>
      raw == 'pool' ? CourierPayKind.pool : CourierPayKind.shop;
}

/// One rate version (never edited; a newer one supersedes it).
class CourierPayRate {
  const CourierPayRate({
    required this.versionId,
    required this.kind,
    required this.perPackageMinorUnits,
    required this.hourlyMinorUnits,
    required this.effectiveFromDate,
  });

  final String versionId;
  final CourierPayKind kind;
  final int perPackageMinorUnits;
  final int? hourlyMinorUnits;
  final String effectiveFromDate;

  factory CourierPayRate.fromJson(Map<String, dynamic> json) => CourierPayRate(
        versionId: json['versionId'] as String? ?? '',
        kind: CourierPayKind.parse(json['courierKind']),
        perPackageMinorUnits: _int(json['perPackageMinorUnits']),
        hourlyMinorUnits: (json['hourlyMinorUnits'] as num?)?.toInt(),
        effectiveFromDate: json['effectiveFromDate'] as String? ?? '',
      );

  /// "Paket başı 40 TL · Saatlik 150 TL".
  String get summary => [
        'Paket başı ${formatPayAmount(perPackageMinorUnits)}',
        if (kind == CourierPayKind.shop && hourlyMinorUnits != null)
          'Saatlik ${formatPayAmount(hourlyMinorUnits!)}',
      ].join(' · ');
}

/// What the staff form sends: a new rate, from [effectiveFromDate] (today
/// when `null`; the server refuses a past date).
class CourierPayRateInput {
  const CourierPayRateInput({
    required this.kind,
    required this.perPackageMinorUnits,
    this.hourlyMinorUnits,
    this.effectiveFromDate,
    this.issuesInvoice,
  });

  final CourierPayKind kind;
  final int perPackageMinorUnits;
  final int? hourlyMinorUnits;
  final String? effectiveFromDate;

  /// Stage 6A — "Fatura Keser", sent with the first rate ("Personel Ekle").
  final bool? issuesInvoice;

  Map<String, dynamic> toJson() => {
        'courierKind': kind.name,
        'perPackageMinorUnits': perPackageMinorUnits,
        if (kind == CourierPayKind.shop) 'hourlyMinorUnits': hourlyMinorUnits,
        if (effectiveFromDate != null) 'effectiveFromDate': effectiveFromDate,
        if (issuesInvoice != null) 'issuesInvoice': issuesInvoice,
      };

  /// Whether this input would change [current] (a different kind or amount).
  bool differsFrom(CourierPayRate? current) =>
      current == null ||
      current.kind != kind ||
      current.perPackageMinorUnits != perPackageMinorUnits ||
      (kind == CourierPayKind.shop &&
          current.hourlyMinorUnits != hourlyMinorUnits) ||
      (effectiveFromDate != null &&
          effectiveFromDate != current.effectiveFromDate);
}

enum CourierShiftStatus {
  startRequested,
  active,
  endRequested,
  closed,
  rejected;

  String get label => switch (this) {
        CourierShiftStatus.startRequested => 'Başlangıç onayı bekliyor',
        CourierShiftStatus.active => 'Vardiyada',
        CourierShiftStatus.endRequested => 'Bitiş onayı bekliyor',
        CourierShiftStatus.closed => 'Kapandı',
        CourierShiftStatus.rejected => 'Reddedildi',
      };

  bool get waitsForManager =>
      this == CourierShiftStatus.startRequested ||
      this == CourierShiftStatus.endRequested;

  static CourierShiftStatus parse(Object? raw) =>
      CourierShiftStatus.values.firstWhere((s) => s.name == raw,
          orElse: () => CourierShiftStatus.closed);
}

class CourierShift {
  const CourierShift({
    required this.shiftId,
    required this.branchId,
    required this.staffUid,
    required this.courierName,
    required this.status,
    required this.requestedStartAt,
    this.approvedStartAt,
    this.requestedEndAt,
    this.approvedEndAt,
    this.approvedMinutes,
  });

  final String shiftId;
  final String branchId;
  final String staffUid;
  final String courierName;
  final CourierShiftStatus status;
  final DateTime requestedStartAt;
  final DateTime? approvedStartAt;
  final DateTime? requestedEndAt;
  final DateTime? approvedEndAt;
  final int? approvedMinutes;

  /// The time the manager is asked about now: the pressed start, or the
  /// pressed end.
  DateTime get pendingTime =>
      status == CourierShiftStatus.endRequested && requestedEndAt != null
          ? requestedEndAt!
          : requestedStartAt;

  factory CourierShift.fromJson(Map<String, dynamic> json) => CourierShift(
        shiftId: json['shiftId'] as String? ?? '',
        branchId: json['branchId'] as String? ?? '',
        staffUid: json['staffUid'] as String? ?? '',
        courierName: json['courierName'] as String? ?? '',
        status: CourierShiftStatus.parse(json['status']),
        requestedStartAt: _time(json['requestedStartAtMillis']) ?? DateTime(0),
        approvedStartAt: _time(json['approvedStartAtMillis']),
        requestedEndAt: _time(json['requestedEndAtMillis']),
        approvedEndAt: _time(json['approvedEndAtMillis']),
        approvedMinutes: (json['approvedMinutes'] as num?)?.toInt(),
      );
}

enum CourierEarningKind { package, shift }

class CourierEarningLine {
  const CourierEarningLine({
    required this.lineId,
    required this.kind,
    required this.orderNumber,
    required this.unitRateMinorUnits,
    required this.quantity,
    required this.amountMinorUnits,
    required this.earnedAt,
    required this.earnedDate,
  });

  final String lineId;
  final CourierEarningKind kind;
  final String? orderNumber;
  final int unitRateMinorUnits;
  final int quantity;
  final int amountMinorUnits;
  final DateTime earnedAt;
  final String earnedDate;

  /// "Paket DL-0012" / "Vardiya 7 sa 23 dk".
  String get title => kind == CourierEarningKind.package
      ? 'Paket ${orderNumber ?? ''}'.trim()
      : 'Vardiya ${formatShiftMinutes(quantity)}';

  factory CourierEarningLine.fromJson(Map<String, dynamic> json) =>
      CourierEarningLine(
        lineId: json['lineId'] as String? ?? '',
        kind: json['kind'] == 'shift'
            ? CourierEarningKind.shift
            : CourierEarningKind.package,
        orderNumber: json['orderNumber'] as String?,
        unitRateMinorUnits: _int(json['unitRateMinorUnits']),
        quantity: _int(json['quantity']),
        amountMinorUnits: _int(json['amountMinorUnits']),
        earnedAt: _time(json['earnedAtMillis']) ?? DateTime(0),
        earnedDate: json['earnedDate'] as String? ?? '',
      );
}

class CourierEarningsTotals {
  const CourierEarningsTotals({
    required this.packageCount,
    required this.packageMinorUnits,
    required this.shiftMinutes,
    required this.shiftMinorUnits,
    required this.totalMinorUnits,
  });

  final int packageCount;
  final int packageMinorUnits;
  final int shiftMinutes;
  final int shiftMinorUnits;
  final int totalMinorUnits;

  factory CourierEarningsTotals.fromJson(Map<String, dynamic> json) =>
      CourierEarningsTotals(
        packageCount: _int(json['packageCount']),
        packageMinorUnits: _int(json['packageMinorUnits']),
        shiftMinutes: _int(json['shiftMinutes']),
        shiftMinorUnits: _int(json['shiftMinorUnits']),
        totalMinorUnits: _int(json['totalMinorUnits']),
      );
}

/// Stage 6A — what the courier has earned in total, been paid in total, and
/// is still owed ("Kalan Bakiye"), across all time.
class CourierBalance {
  const CourierBalance({
    required this.earnedTotalMinorUnits,
    required this.paidTotalMinorUnits,
    required this.balanceMinorUnits,
  });

  final int earnedTotalMinorUnits;
  final int paidTotalMinorUnits;
  final int balanceMinorUnits;

  factory CourierBalance.fromJson(Map<String, dynamic> json) => CourierBalance(
        earnedTotalMinorUnits: _int(json['earnedTotalMinorUnits']),
        paidTotalMinorUnits: _int(json['paidTotalMinorUnits']),
        balanceMinorUnits: _int(json['balanceMinorUnits']),
      );
}

enum CourierInvoiceStatus {
  submitted,
  approved,
  partiallyPaid,
  paid,
  rejected;

  String get label => switch (this) {
        CourierInvoiceStatus.submitted => 'Onay Bekliyor',
        CourierInvoiceStatus.approved => 'Onaylandı',
        CourierInvoiceStatus.partiallyPaid => 'Kısmi Ödendi',
        CourierInvoiceStatus.paid => 'Ödendi',
        CourierInvoiceStatus.rejected => 'Reddedildi',
      };

  /// An approved invoice that still has something left to pay.
  bool get payable =>
      this == CourierInvoiceStatus.approved ||
      this == CourierInvoiceStatus.partiallyPaid;

  static CourierInvoiceStatus parse(Object? raw) =>
      CourierInvoiceStatus.values.firstWhere((s) => s.name == raw,
          orElse: () => CourierInvoiceStatus.submitted);
}

class CourierInvoice {
  const CourierInvoice({
    required this.invoiceId,
    required this.staffUid,
    required this.courierName,
    required this.periodFrom,
    required this.periodTo,
    required this.lineCount,
    required this.earnedMinorUnits,
    required this.invoiceAmountMinorUnits,
    required this.invoiceNumber,
    required this.note,
    required this.contentType,
    required this.status,
    required this.rejectReason,
    required this.paidMinorUnits,
    required this.remainingMinorUnits,
  });

  final String invoiceId;
  final String staffUid;
  final String courierName;
  final String periodFrom;
  final String periodTo;
  final int lineCount;

  /// What the system computed for the invoiced lines.
  final int earnedMinorUnits;

  /// What the invoice says (VAT, withholding may make it differ).
  final int invoiceAmountMinorUnits;
  final String invoiceNumber;
  final String? note;
  final String contentType;
  final CourierInvoiceStatus status;
  final String? rejectReason;
  final int paidMinorUnits;
  final int remainingMinorUnits;

  int get differenceMinorUnits => invoiceAmountMinorUnits - earnedMinorUnits;
  bool get isPdf => contentType == 'application/pdf';
  String get period => '$periodFrom – $periodTo';

  factory CourierInvoice.fromJson(Map<String, dynamic> json) => CourierInvoice(
        invoiceId: json['invoiceId'] as String? ?? '',
        staffUid: json['staffUid'] as String? ?? '',
        courierName: json['courierName'] as String? ?? '',
        periodFrom: json['periodFrom'] as String? ?? '',
        periodTo: json['periodTo'] as String? ?? '',
        lineCount: _int(json['lineCount']),
        earnedMinorUnits: _int(json['earnedMinorUnits']),
        invoiceAmountMinorUnits: _int(json['invoiceAmountMinorUnits']),
        invoiceNumber: json['invoiceNumber'] as String? ?? '',
        note: json['note'] as String?,
        contentType: json['contentType'] as String? ?? '',
        status: CourierInvoiceStatus.parse(json['status']),
        rejectReason: json['rejectReason'] as String?,
        paidMinorUnits: _int(json['paidMinorUnits']),
        remainingMinorUnits: _int(json['remainingMinorUnits']),
      );
}

enum CourierPaymentKind {
  invoicePayment,
  advance,
  reversal;

  String get label => switch (this) {
        CourierPaymentKind.invoicePayment => 'Fatura Ödemesi',
        CourierPaymentKind.advance => 'Avans',
        CourierPaymentKind.reversal => 'Düzeltme (geri alındı)',
      };

  static CourierPaymentKind parse(Object? raw) =>
      CourierPaymentKind.values.firstWhere((k) => k.name == raw,
          orElse: () => CourierPaymentKind.advance);
}

class CourierPayment {
  const CourierPayment({
    required this.paymentId,
    required this.kind,
    required this.amountMinorUnits,
    required this.paidDate,
    required this.invoiceId,
    required this.reversed,
    required this.note,
  });

  final String paymentId;
  final CourierPaymentKind kind;

  /// Negative for a reversal.
  final int amountMinorUnits;
  final String paidDate;
  final String? invoiceId;

  /// Already undone by a later reversal.
  final bool reversed;
  final String? note;

  bool get reversible => kind != CourierPaymentKind.reversal && !reversed;

  factory CourierPayment.fromJson(Map<String, dynamic> json) => CourierPayment(
        paymentId: json['paymentId'] as String? ?? '',
        kind: CourierPaymentKind.parse(json['kind']),
        amountMinorUnits: _int(json['amountMinorUnits']),
        paidDate: json['paidDate'] as String? ?? '',
        invoiceId: json['invoiceId'] as String?,
        reversed: json['reversedByPaymentId'] is String,
        note: json['note'] as String?,
      );
}

/// "Fatura Yükle" step 1: what a period would invoice.
class CourierInvoicePreview {
  const CourierInvoicePreview({
    required this.lineCount,
    required this.earnedMinorUnits,
    required this.carriedLineCount,
    required this.overlapping,
  });

  final int lineCount;
  final int earnedMinorUnits;

  /// Lines from before the period that were never invoiced.
  final int carriedLineCount;

  /// Another active invoice already covers part of the period.
  final bool overlapping;

  factory CourierInvoicePreview.fromJson(Map<String, dynamic> json) =>
      CourierInvoicePreview(
        lineCount: _int(json['lineCount']),
        earnedMinorUnits: _int(json['earnedMinorUnits']),
        carriedLineCount: _int(json['carriedLineCount']),
        overlapping: json['overlappingInvoiceId'] is String,
      );
}

/// The invoices the panel lists, and whether the caller may pay them.
class CourierInvoiceList {
  const CourierInvoiceList({
    required this.invoices,
    required this.canRecordPayments,
  });

  final List<CourierInvoice> invoices;
  final bool canRecordPayments;
}

/// The staff edit form's view of a courier's pay.
class CourierPayProfileSummary {
  const CourierPayProfileSummary({
    required this.currentRate,
    required this.issuesInvoice,
  });

  final CourierPayRate? currentRate;
  final bool issuesInvoice;
}

/// One courier's earnings in a period (manager/admin view).
class CourierEarningsEntry {
  const CourierEarningsEntry({
    required this.staffUid,
    required this.courierName,
    required this.totals,
    required this.lines,
    this.issuesInvoice = false,
    this.paidInPeriodMinorUnits = 0,
    this.balance = const CourierBalance(
      earnedTotalMinorUnits: 0,
      paidTotalMinorUnits: 0,
      balanceMinorUnits: 0,
    ),
    this.payments = const [],
  });

  final String staffUid;
  final String courierName;
  final CourierEarningsTotals totals;
  final List<CourierEarningLine> lines;
  final bool issuesInvoice;
  final int paidInPeriodMinorUnits;
  final CourierBalance balance;
  final List<CourierPayment> payments;

  factory CourierEarningsEntry.fromJson(Map<String, dynamic> json) =>
      CourierEarningsEntry(
        staffUid: json['staffUid'] as String? ?? '',
        courierName: json['courierName'] as String? ?? '',
        totals: CourierEarningsTotals.fromJson(json),
        lines: _lines(json['lines']),
        issuesInvoice: json['issuesInvoice'] == true,
        paidInPeriodMinorUnits: _int(json['paidInPeriodMinorUnits']),
        balance: CourierBalance.fromJson(json),
        payments: [
          for (final p in _maps(json['payments'])) CourierPayment.fromJson(p)
        ],
      );
}

class CourierEarningsReport {
  const CourierEarningsReport({
    required this.totalMinorUnits,
    required this.truncated,
    required this.couriers,
    this.paidInPeriodMinorUnits = 0,
    this.canRecordPayments = false,
  });

  final int totalMinorUnits;
  final bool truncated;
  final List<CourierEarningsEntry> couriers;
  final int paidInPeriodMinorUnits;
  final bool canRecordPayments;

  factory CourierEarningsReport.fromJson(Map<String, dynamic> json) =>
      CourierEarningsReport(
        totalMinorUnits: _int(json['totalMinorUnits']),
        truncated: json['truncated'] == true,
        couriers: [
          for (final c in _maps(json['couriers']))
            CourierEarningsEntry.fromJson(c),
        ],
        paidInPeriodMinorUnits: _int(json['paidInPeriodMinorUnits']),
        canRecordPayments: json['canRecordPayments'] == true,
      );
}

/// The courier app's "Kazancım".
class MyCourierPay {
  const MyCourierPay({
    required this.shiftsEnabled,
    required this.currentRate,
    required this.openShift,
    required this.totals,
    required this.lines,
    this.issuesInvoice = false,
    this.paidInPeriodMinorUnits = 0,
    this.balance = const CourierBalance(
      earnedTotalMinorUnits: 0,
      paidTotalMinorUnits: 0,
      balanceMinorUnits: 0,
    ),
    this.payments = const [],
    this.invoices = const [],
  });

  final bool shiftsEnabled;
  final CourierPayRate? currentRate;
  final CourierShift? openShift;
  final CourierEarningsTotals totals;
  final List<CourierEarningLine> lines;
  final bool issuesInvoice;
  final int paidInPeriodMinorUnits;
  final CourierBalance balance;
  final List<CourierPayment> payments;
  final List<CourierInvoice> invoices;

  factory MyCourierPay.fromJson(Map<String, dynamic> json) => MyCourierPay(
        shiftsEnabled: json['shiftsEnabled'] == true,
        currentRate: json['currentRate'] is Map
            ? CourierPayRate.fromJson(
                Map<String, dynamic>.from(json['currentRate'] as Map))
            : null,
        openShift: json['openShift'] is Map
            ? CourierShift.fromJson(
                Map<String, dynamic>.from(json['openShift'] as Map))
            : null,
        totals: CourierEarningsTotals.fromJson(json),
        lines: _lines(json['lines']),
        issuesInvoice: json['issuesInvoice'] == true,
        paidInPeriodMinorUnits: _int(json['paidInPeriodMinorUnits']),
        balance: CourierBalance.fromJson(json),
        payments: [
          for (final p in _maps(json['payments'])) CourierPayment.fromJson(p)
        ],
        invoices: [
          for (final i in _maps(json['invoices'])) CourierInvoice.fromJson(i)
        ],
      );
}

/// A report period: Istanbul calendar days, both ends included.
typedef CourierPayRange = ({String fromDate, String toDate});

/// The longest period a report or an invoice may cover (a year).
const courierPayMaxRangeDays = 366;

/// The period chips of both earnings views.
enum CourierPayPeriod {
  today,
  thisWeek,
  thisMonth;

  String get label => switch (this) {
        CourierPayPeriod.today => 'Bugün',
        CourierPayPeriod.thisWeek => 'Bu Hafta',
        CourierPayPeriod.thisMonth => 'Bu Ay',
      };

  /// `(fromDate, toDate)` as Istanbul calendar days; weeks start on Monday.
  ({String fromDate, String toDate}) range(DateTime now) {
    final today = istanbulDay(now);
    final from = switch (this) {
      CourierPayPeriod.today => today,
      CourierPayPeriod.thisWeek =>
        today.subtract(Duration(days: today.weekday - DateTime.monday)),
      CourierPayPeriod.thisMonth => DateTime.utc(today.year, today.month),
    };
    return (fromDate: isoDay(from), toDate: isoDay(today));
  }
}

/// Turkey is UTC+3 all year: the calendar day there, as a UTC midnight.
DateTime istanbulDay(DateTime moment) {
  final local = moment.toUtc().add(const Duration(hours: 3));
  return DateTime.utc(local.year, local.month, local.day);
}

String isoDay(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// "1.476,67 TL" — whole lira without decimals ("150 TL").
String formatPayAmount(int minorUnits) {
  final negative = minorUnits < 0;
  final abs = minorUnits.abs();
  final lira = (abs ~/ 100).toString();
  final grouped = StringBuffer();
  for (var i = 0; i < lira.length; i++) {
    if (i > 0 && (lira.length - i) % 3 == 0) grouped.write('.');
    grouped.write(lira[i]);
  }
  final kurus = abs % 100;
  final body =
      kurus == 0 ? '$grouped' : '$grouped,${kurus.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}$body TL';
}

/// "7 sa 23 dk" / "45 dk".
String formatShiftMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest dk';
  return rest == 0 ? '$hours sa' : '$hours sa $rest dk';
}

/// Parses a lira amount as typed ("150", "150,5", "150.50") into kuruş;
/// `null` when it is not a non-negative amount with at most 2 decimals.
int? parseLiraToMinorUnits(String text) {
  final normalized = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  final match = RegExp(r'^(\d{1,6})(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) return null;
  final lira = int.parse(match.group(1)!);
  final kurus = int.parse((match.group(2) ?? '0').padRight(2, '0'));
  return lira * 100 + kurus;
}

/// The amount as the form shows it ("150" / "150,50").
String minorUnitsToLiraText(int minorUnits) {
  final kurus = minorUnits % 100;
  final lira = minorUnits ~/ 100;
  return kurus == 0 ? '$lira' : '$lira,${kurus.toString().padLeft(2, '0')}';
}

int _int(Object? raw) => (raw as num?)?.toInt() ?? 0;

List<Map<String, dynamic>> _maps(Object? raw) => [
      for (final item in (raw as List? ?? const []))
        Map<String, dynamic>.from(item as Map),
    ];

DateTime? _time(Object? raw) => raw is num
    ? DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true).toLocal()
    : null;

List<CourierEarningLine> _lines(Object? raw) => [
      for (final line in (raw as List? ?? const []))
        CourierEarningLine.fromJson(Map<String, dynamic>.from(line as Map)),
    ];
