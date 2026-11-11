import 'meal_card_revenue_line.dart';

/// Everything a Z-Raporu receipt needs to render — assembled by the caller
/// from already-fetched `CashSessionView`/`DailyRevenueSummary`/
/// `CashCountResult` data, never re-fetched here. Domain model, not a
/// data-layer type — `EscPosZReportEncoder`
/// (`features/printing/domain/esc_pos_z_report_encoder.dart`) depends on
/// this file directly, mirroring `EscPosKitchenTicketEncoder`'s own
/// identical cross-feature-domain dependency on `KitchenTicket`.
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
    this.mealCardBreakdown = const [],
    required this.totalMinorUnits,
    required this.expectedAmountMinorUnits,
    required this.actualAmountMinorUnits,
    required this.varianceType,
    required this.varianceAmountMinorUnits,
    this.complimentaryMinorUnits = 0,
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

  /// 2026-11-11 — one line per meal-card brand, listed after "Kredi Kartı".
  final List<MealCardRevenueLine> mealCardBreakdown;
  final int totalMinorUnits;
  final int expectedAmountMinorUnits;
  final int actualAmountMinorUnits;
  final String varianceType; // 'over' | 'short' | 'exact'
  final int varianceAmountMinorUnits;

  /// Adım 3 (2026-11-06) — "İkram Toplamı" for the Z-Raporu: the sum of
  /// every active `checkFinancialAdjustments` doc for this session (a
  /// reversed comp nets to zero on its own, server-side). **Disclosed
  /// scope**: comp (İkram) only — a cancelled-line value total ("İptal
  /// Toplamı") isn't included; see `getDailyRevenueSummary`'s own doc
  /// comment (`functions/src/cashRegisterEngine.ts`) for why.
  final int complimentaryMinorUnits;

  String _fmt(int minorUnits) =>
      '$currencySymbol${(minorUnits / 100).toStringAsFixed(2)}';

  String get varianceLabel => switch (varianceType) {
        'over' => 'Fazla',
        'short' => 'Eksik',
        _ => 'Tam',
      };

  /// Plain-text, fixed-width-friendly Z-Raporu content — shown on-screen
  /// as the "Yazdırmaya Hazır" preview regardless of whether the real
  /// print (`EscPosZReportEncoder` via `WindowsZReportPrinterAdapter`)
  /// actually succeeds.
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
      ..writeln('Kredi Kartı: ${_fmt(cardMinorUnits)}');
    for (final line in mealCardBreakdown) {
      buffer.writeln('${line.displayName}: ${_fmt(line.amountMinorUnits)}');
    }
    buffer
      ..writeln('Diğer: ${_fmt(otherMinorUnits)}')
      ..writeln('TOPLAM CİRO: ${_fmt(totalMinorUnits)}')
      ..writeln('-' * 32)
      ..writeln('İkram Toplamı: ${_fmt(complimentaryMinorUnits)}')
      ..writeln('-' * 32)
      ..writeln('Beklenen Nakit: ${_fmt(expectedAmountMinorUnits)}')
      ..writeln('Sayılan Nakit: ${_fmt(actualAmountMinorUnits)}')
      ..writeln('Fark: $varianceLabel ${_fmt(varianceAmountMinorUnits)}')
      ..writeln('=' * 32);
    return buffer.toString();
  }
}
