import 'dart:typed_data';

import '../../pos/domain/cash/z_report_content.dart';
import 'receipt_codepage.dart';
import 'turkish_ascii_transliteration.dart';

/// Encodes a [ZReportContent] into the raw ESC/POS byte stream for an
/// 80mm thermal printer — Adım 3 (2026-11-06), "Gün Sonu / Z Raporu".
/// Mirrors `EscPosReceiptEncoder`/`EscPosKitchenTicketEncoder`'s exact
/// primitives/codepage choice (kept as its own self-contained encoder,
/// same reasoning as those two: the Z-Raporu's layout is genuinely
/// different, and this never touches either existing encoder). See
/// [ReceiptCodepage]'s own doc comment for how the codepage choice was
/// verified (physical self-test), not guessed.
abstract final class EscPosZReportEncoder {
  EscPosZReportEncoder._();

  static const int _lineWidth = 48;

  static const List<int> _init = [0x1B, 0x40]; // ESC @
  static List<int> _selectCodepage(ReceiptCodepage codepage) =>
      [0x1B, 0x74, codepage == ReceiptCodepage.pc857 ? 19 : 45]; // ESC t n
  static List<int> _align(int n) => [0x1B, 0x61, n]; // ESC a n
  static List<int> _bold(bool on) => [0x1B, 0x45, on ? 1 : 0]; // ESC E n
  static List<int> _size(int n) => [0x1D, 0x21, n]; // GS ! n
  static const List<int> _feedAndCut = [0x1D, 0x56, 66, 0]; // GS V 66 0

  static Uint8List encode(
    ZReportContent content, {
    ReceiptCodepage codepage = ReceiptCodepage.wpc1254,
  }) {
    final bytes = <int>[];
    bytes.addAll(_init);
    bytes.addAll(_selectCodepage(codepage));

    void writeLine(String text, {bool bold = false, bool center = false}) {
      bytes.addAll(_align(center ? 1 : 0));
      bytes.addAll(_bold(bold));
      bytes.addAll(_encodeTurkish(text, codepage));
      bytes.addAll(_encodeTurkish('\n', codepage));
      bytes.addAll(_bold(false));
      bytes.addAll(_align(0));
    }

    void writeTwoColumn(String left, String right, {bool bold = false}) {
      writeLine(_twoColumn(left, right), bold: bold);
    }

    // Header.
    bytes.addAll(_size(0x11)); // double width + height
    writeLine('Z RAPORU', bold: true, center: true);
    bytes.addAll(_size(0x00));
    writeLine(content.branchDisplayName, center: true);
    writeLine('Tarih: ${content.businessDate}', center: true);
    writeLine('Kasa Oturumu: ${content.sessionId}', center: true);
    writeLine('-' * _lineWidth);
    writeLine('Açılış: ${_formatDateTime(content.openedAt)}');
    writeLine('Kapanış: ${_formatDateTime(content.closedAt)}');
    writeLine('-' * _lineWidth);

    writeTwoColumn(
        'Açılış Bakiyesi', _fmt(content, content.openingFloatMinorUnits));
    writeLine('-' * _lineWidth);
    writeTwoColumn('Nakit', _fmt(content, content.cashMinorUnits));
    writeTwoColumn('Kredi Kartı', _fmt(content, content.cardMinorUnits));
    for (final line in content.mealCardBreakdown) {
      writeTwoColumn(line.displayName, _fmt(content, line.amountMinorUnits));
    }
    writeTwoColumn('Diğer', _fmt(content, content.otherMinorUnits));
    bytes.addAll(_size(0x11));
    writeTwoColumn('TOPLAM CİRO', _fmt(content, content.totalMinorUnits),
        bold: true);
    bytes.addAll(_size(0x00));
    writeLine('-' * _lineWidth);
    // "İptal/İkram Toplamı" — disclosed scope: İkram (comp) only, see
    // `ZReportContent.complimentaryMinorUnits`'s own doc comment for why
    // a cancelled-line value total isn't included.
    writeTwoColumn(
        'İkram Toplamı', _fmt(content, content.complimentaryMinorUnits));
    writeLine('-' * _lineWidth);
    writeTwoColumn(
        'Beklenen Nakit', _fmt(content, content.expectedAmountMinorUnits));
    writeTwoColumn(
        'Sayılan Nakit', _fmt(content, content.actualAmountMinorUnits));
    writeTwoColumn('Kasa Farkı (${content.varianceLabel})',
        _fmt(content, content.varianceAmountMinorUnits),
        bold: content.varianceType != 'exact');
    writeLine('=' * _lineWidth);

    writeLine('');
    bytes.addAll(_feedAndCut);
    return Uint8List.fromList(bytes);
  }

  static String _fmt(ZReportContent content, int minorUnits) =>
      '${content.currencySymbol}${(minorUnits / 100).toStringAsFixed(2)}';

  static String _twoColumn(String left, String right) {
    final maxLeft = _lineWidth - right.length - 1;
    final clippedLeft =
        left.length > maxLeft ? left.substring(0, maxLeft) : left;
    final padding = _lineWidth - clippedLeft.length - right.length;
    return '$clippedLeft${' ' * (padding > 0 ? padding : 1)}$right';
  }

  static String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// Identical table/reasoning to `EscPosReceiptEncoder._encodeTurkish` —
  /// see that method's own doc comment.
  static List<int> _encodeTurkish(String rawText, ReceiptCodepage codepage) {
    // 2026-11-08 — see turkish_ascii_transliteration.dart's own doc comment.
    final text = transliterateTurkishToAscii(rawText);
    if (codepage == ReceiptCodepage.pc857) {
      const pc857 = <int, int>{
        0x00C7: 0x80, // Ç
        0x00E7: 0x87, // ç
        0x00D6: 0x99, // Ö
        0x00F6: 0x94, // ö
        0x00DC: 0x9A, // Ü
        0x00FC: 0x81, // ü
        0x011E: 0xA6, // Ğ
        0x011F: 0xA7, // ğ
        0x0130: 0x98, // İ
        0x0131: 0x8D, // ı
        0x015E: 0x9E, // Ş
        0x015F: 0x9F, // ş
      };
      final out = <int>[];
      for (final rune in text.runes) {
        if (rune <= 0x7F) {
          out.add(rune);
        } else if (pc857.containsKey(rune)) {
          out.add(pc857[rune]!);
        } else {
          out.add(0x3F); // '?'
        }
      }
      return out;
    }

    const wpc1254 = <int, int>{
      0x011E: 0xD0, // Ğ
      0x011F: 0xF0, // ğ
      0x0130: 0xDD, // İ
      0x0131: 0xFD, // ı
      0x015E: 0xDE, // Ş
      0x015F: 0xFE, // ş
    };
    final out = <int>[];
    for (final rune in text.runes) {
      if (rune <= 0xFF) {
        out.add(rune);
      } else if (wpc1254.containsKey(rune)) {
        out.add(wpc1254[rune]!);
      } else {
        out.add(0x3F); // '?'
      }
    }
    return out;
  }
}
