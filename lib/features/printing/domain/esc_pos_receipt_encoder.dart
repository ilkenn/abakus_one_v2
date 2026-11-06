import 'dart:typed_data';

import 'receipt_codepage.dart';
import 'receipt_document.dart';

/// Encodes a [ReceiptDocument] into the raw ESC/POS byte stream for an
/// 80mm thermal till printer (~48-character line width at the printer's
/// default font) — 2026-11-05 real printer integration.
///
/// **Codepage, verified against this specific physical unit's own
/// self-test page (2026-11-06)**, not guessed: its default is CP437 (no
/// Turkish support), and [ReceiptCodepage.wpc1254] (`ESC t 45`) is the
/// primary attempt — the one table of the two with full Turkish letter
/// support. If that still doesn't render correctly on the physical
/// printer, pass [ReceiptCodepage.pc857] instead (same self-test page,
/// `ESC t 19`) — see [ReceiptCodepage]'s own doc comment for why neither
/// index matches the "standard" Epson TM-series numbering this file
/// originally (incorrectly) assumed.
abstract final class EscPosReceiptEncoder {
  EscPosReceiptEncoder._();

  static const int _lineWidth = 48;

  static const List<int> _init = [0x1B, 0x40]; // ESC @
  static List<int> _selectCodepage(ReceiptCodepage codepage) =>
      [0x1B, 0x74, codepage == ReceiptCodepage.pc857 ? 19 : 45]; // ESC t n
  static List<int> _align(int n) => [0x1B, 0x61, n]; // ESC a n
  static List<int> _bold(bool on) => [0x1B, 0x45, on ? 1 : 0]; // ESC E n
  static List<int> _size(int n) => [0x1D, 0x21, n]; // GS ! n
  static const List<int> _feedAndCut = [0x1D, 0x56, 66, 0]; // GS V 66 0

  static Uint8List encode(
    ReceiptDocument doc, {
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
    writeLine(doc.restaurantName, bold: true, center: true);
    bytes.addAll(_size(0x00));
    writeLine(doc.branchName, center: true);
    writeLine('Masa: ${doc.tableName}', center: true);
    writeLine(_formatDateTime(doc.issuedAt), center: true);
    writeLine('Fiş No: ${doc.receiptNumber}', center: true);
    writeLine('-' * _lineWidth);

    // Lines.
    for (final line in doc.lines) {
      writeTwoColumn(
        '${line.quantity} x ${line.productName}',
        _formatAmount(line.totalPriceMinorUnits, doc.currencyCode),
        bold: true,
      );
      if (line.recipeSummary != null) {
        writeLine('  ${line.recipeSummary}');
      }
      for (final note in line.selectionNotes) {
        writeLine('  $note');
      }
    }
    writeLine('-' * _lineWidth);

    // Totals.
    writeTwoColumn(
        'Ara Toplam', _formatAmount(doc.subtotalMinorUnits, doc.currencyCode));
    if (doc.discountMinorUnits > 0) {
      writeTwoColumn('İndirim',
          '-${_formatAmount(doc.discountMinorUnits, doc.currencyCode)}');
    }
    bytes.addAll(_size(0x11));
    writeTwoColumn(
        'TOPLAM', _formatAmount(doc.totalMinorUnits, doc.currencyCode),
        bold: true);
    bytes.addAll(_size(0x00));
    writeLine('(KDV Dahildir)', center: true);
    writeLine('');
    writeLine('Afiyet Olsun', center: true);
    writeLine('');
    writeLine('');
    bytes.addAll(_feedAndCut);
    return Uint8List.fromList(bytes);
  }

  static String _twoColumn(String left, String right) {
    final maxLeft = _lineWidth - right.length - 1;
    final clippedLeft =
        left.length > maxLeft ? left.substring(0, maxLeft) : left;
    final padding = _lineWidth - clippedLeft.length - right.length;
    return '$clippedLeft${' ' * (padding > 0 ? padding : 1)}$right';
  }

  // '₺' (U+20BA) has no slot in any classic 8-bit ESC/POS codepage table
  // (CP1254/CP857/CP850/...) — every one of them predates the Turkish
  // Lira symbol itself, so sending it always fell back to '?' regardless
  // of which table was selected. 'TL' prints correctly everywhere,
  // exactly as requested (2026-11-06 physical print test).
  static String _formatAmount(int minorUnits, String currencyCode) {
    final symbol = currencyCode == 'TRY' ? 'TL' : currencyCode;
    return '${(minorUnits / 100).toStringAsFixed(2)} $symbol';
  }

  static String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// [ReceiptCodepage.wpc1254] — Windows-1254 (CP1254): identical to
  /// Latin-1 for every byte this receipt actually needs except the six
  /// Turkish letters Latin-1 doesn't have a correct slot for (verified
  /// against a real `windows-1254` codec, 2026-11-06 — not assumed).
  ///
  /// [ReceiptCodepage.pc857]: a genuinely different, DOS-era byte layout
  /// in the 0x80–0xFF range — NOT Latin-1-compatible like [wpc1254] is, so
  /// this path cannot reuse the same "pass through ≤0xFF" shortcut; only
  /// plain ASCII (≤0x7F) and the explicit Turkish-letter table below are
  /// safe to send (byte values verified against a real `cp857` codec,
  /// `iconv-lite`, 2026-11-06 — not guessed, unlike this file's original
  /// WPC1254-only attempt).
  ///
  /// Either way, anything outside what the selected table actually
  /// supports falls back to `?` rather than sending an undefined byte.
  static List<int> _encodeTurkish(String text, ReceiptCodepage codepage) {
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
