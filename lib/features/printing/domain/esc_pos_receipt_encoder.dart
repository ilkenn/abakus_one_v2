import 'dart:typed_data';

import 'receipt_document.dart';

/// Encodes a [ReceiptDocument] into the raw ESC/POS byte stream for an
/// 80mm thermal till printer (~48-character line width at the printer's
/// default font) — 2026-11-05 real printer integration.
///
/// **Best-effort codepage, not vendor-verified**: `docs
/// /kds_printer_stock_architecture.md` §14/§24 explicitly gates a real
/// `PrinterAdapter` on the target hardware's own ESC/POS reference manual,
/// which isn't available for the confirmed "POS80 Printer" (generic 80mm
/// USB clone) — only its Windows queue name and the standard ESC/POS
/// protocol are known. This encoder selects Epson's documented "WPC1254"
/// table (`ESC t 45`), the standard Windows-1254 Turkish codepage, since
/// that's the most common convention on this class of printer sold into
/// the Turkish market and matches what Windows itself uses for Turkish
/// text — but it is genuinely unverified against the physical unit. If
/// Turkish characters print garbled, that single table-select byte (or the
/// cut command below) is the first thing to check against the printer's
/// own manual.
abstract final class EscPosReceiptEncoder {
  EscPosReceiptEncoder._();

  static const int _lineWidth = 48;

  static const List<int> _init = [0x1B, 0x40]; // ESC @
  static const List<int> _selectWpc1254 = [0x1B, 0x74, 45]; // ESC t 45
  static List<int> _align(int n) => [0x1B, 0x61, n]; // ESC a n
  static List<int> _bold(bool on) => [0x1B, 0x45, on ? 1 : 0]; // ESC E n
  static List<int> _size(int n) => [0x1D, 0x21, n]; // GS ! n
  static const List<int> _feedAndCut = [0x1D, 0x56, 66, 0]; // GS V 66 0

  static Uint8List encode(ReceiptDocument doc) {
    final bytes = <int>[];
    bytes.addAll(_init);
    bytes.addAll(_selectWpc1254);

    void writeLine(String text, {bool bold = false, bool center = false}) {
      bytes.addAll(_align(center ? 1 : 0));
      bytes.addAll(_bold(bold));
      bytes.addAll(_encodeTurkish(text));
      bytes.addAll(_encodeTurkish('\n'));
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

  /// Windows-1254 (CP1254) encoding — identical to Latin-1/CP1252 for every
  /// byte this receipt actually needs except the six Turkish letters CP1252
  /// doesn't have a correct slot for. Anything outside the Latin-1 range
  /// falls back to `?` rather than crashing or sending an undefined byte.
  static List<int> _encodeTurkish(String text) {
    const overrides = <int, int>{
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
      } else if (overrides.containsKey(rune)) {
        out.add(overrides[rune]!);
      } else {
        out.add(0x3F); // '?'
      }
    }
    return out;
  }
}
