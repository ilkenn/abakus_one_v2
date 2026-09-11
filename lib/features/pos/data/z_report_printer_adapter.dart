/// Gün Sonu (Kasa Kapanışı) — the receipt-printer transport boundary.
///
/// **No real ESC/POS transport exists in this app.** A confirmed check
/// before writing this file found no thermal-printer package in
/// `pubspec.yaml` and no printer transport anywhere in `lib/` — mirrors
/// `functions/src/fiscalAdapter.ts`'s own honest structure for the identical
/// reason: this is real, tested, forward-groundwork code with no live
/// hardware trigger yet, never code that pretends to produce real thermal
/// output. Adding a printer package is a dependency/architecture change
/// (CLAUDE.md §5/§15) — out of this pass's scope.
///
/// [ZReportContent.toReceiptText] is the one real, verifiable artifact this
/// file produces today — the actual plain-text content a real ESC/POS
/// driver would print once a transport is wired in. The screen shows this
/// text on-screen as the "Yazdırmaya Hazır" preview regardless of transport
/// availability.
library;

/// Everything a Z-Raporu receipt needs to render — assembled by the caller
/// from already-fetched [CashSessionView]/[DailyRevenueSummary]/
/// [CashCountResult] data, never re-fetched here.
class ZReportContent {
  const ZReportContent({
    required this.branchDisplayName,
    required this.sessionId,
    required this.businessDate,
    required this.openedAt,
    required this.closedAt,
    required this.currencySymbol,
    required this.openingFloatMinorUnits,
    required this.cashMinorUnits,
    required this.cardMinorUnits,
    required this.otherMinorUnits,
    required this.totalMinorUnits,
    required this.expectedAmountMinorUnits,
    required this.actualAmountMinorUnits,
    required this.varianceType,
    required this.varianceAmountMinorUnits,
  });

  final String branchDisplayName;
  final String sessionId;
  final String businessDate;
  final DateTime openedAt;
  final DateTime closedAt;
  final String currencySymbol;
  final int openingFloatMinorUnits;
  final int cashMinorUnits;
  final int cardMinorUnits;
  final int otherMinorUnits;
  final int totalMinorUnits;
  final int expectedAmountMinorUnits;
  final int actualAmountMinorUnits;
  final String varianceType; // 'over' | 'short' | 'exact'
  final int varianceAmountMinorUnits;

  String _fmt(int minorUnits) =>
      '$currencySymbol${(minorUnits / 100).toStringAsFixed(2)}';

  String get varianceLabel => switch (varianceType) {
        'over' => 'Fazla',
        'short' => 'Eksik',
        _ => 'Tam',
      };

  /// Plain-text, fixed-width-friendly Z-Raporu content — a real ESC/POS
  /// driver could take this as-is once a transport exists.
  String toReceiptText() {
    final buffer = StringBuffer()
      ..writeln('=' * 32)
      ..writeln('Z RAPORU')
      ..writeln(branchDisplayName)
      ..writeln('=' * 32)
      ..writeln('Tarih: $businessDate')
      ..writeln('Kasa Oturumu: $sessionId')
      ..writeln('Açılış: $openedAt')
      ..writeln('Kapanış: $closedAt')
      ..writeln('-' * 32)
      ..writeln('Açılış Bakiyesi: ${_fmt(openingFloatMinorUnits)}')
      ..writeln('-' * 32)
      ..writeln('Nakit: ${_fmt(cashMinorUnits)}')
      ..writeln('Kredi Kartı: ${_fmt(cardMinorUnits)}')
      ..writeln('Diğer: ${_fmt(otherMinorUnits)}')
      ..writeln('TOPLAM CİRO: ${_fmt(totalMinorUnits)}')
      ..writeln('-' * 32)
      ..writeln('Beklenen Nakit: ${_fmt(expectedAmountMinorUnits)}')
      ..writeln('Sayılan Nakit: ${_fmt(actualAmountMinorUnits)}')
      ..writeln('Fark: $varianceLabel ${_fmt(varianceAmountMinorUnits)}')
      ..writeln('=' * 32);
    return buffer.toString();
  }
}

class ZReportPrintResult {
  const ZReportPrintResult({required this.succeeded, required this.message});
  final bool succeeded;
  final String message;
}

abstract interface class ZReportPrinterAdapter {
  Future<ZReportPrintResult> print(ZReportContent content);
}

/// The honest "no real printer is configured" adapter — what this app
/// actually has today. Never fabricates a successful print.
class UnconfiguredZReportPrinterAdapter implements ZReportPrinterAdapter {
  const UnconfiguredZReportPrinterAdapter();

  @override
  Future<ZReportPrintResult> print(ZReportContent content) async {
    return const ZReportPrintResult(
      succeeded: false,
      message:
          'Bu cihazda yapılandırılmış bir ESC/POS yazıcı bağlantısı yok. '
          'Rapor içeriği önizlemede görüntüleniyor.',
    );
  }
}
