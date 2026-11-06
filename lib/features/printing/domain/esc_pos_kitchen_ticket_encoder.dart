import 'dart:typed_data';

import '../../pos/domain/kitchen/kitchen_ticket.dart';
import 'receipt_codepage.dart';

/// Encodes a [KitchenTicket] into the raw ESC/POS byte stream for an 80mm
/// thermal printer — Self-Order QR Faz 5 (23-rule plan §6, "onay sonrası
/// mutfak yazdırma"). Mirrors `EscPosReceiptEncoder`'s exact primitives/
/// codepage choice (kept as a separate, self-contained encoder rather than
/// sharing code with it — a kitchen ticket's layout/required fields are
/// genuinely different from a till receipt's, and the existing receipt
/// encoder stays untouched either way). See [ReceiptCodepage]'s own doc
/// comment for how the codepage choice was verified (2026-11-06 physical
/// self-test), not guessed.
///
/// Per-line required format (23-rule plan §6): Ürün Adı, Adet, Siparişi
/// Veren Kişi Adı, Reçete İçeriği, Tercih Notları — all five are printed
/// for every line, never silently omitted.
abstract final class EscPosKitchenTicketEncoder {
  EscPosKitchenTicketEncoder._();

  static const int _lineWidth = 48;

  static const List<int> _init = [0x1B, 0x40]; // ESC @
  static List<int> _selectCodepage(ReceiptCodepage codepage) =>
      [0x1B, 0x74, codepage == ReceiptCodepage.pc857 ? 19 : 45]; // ESC t n
  static List<int> _align(int n) => [0x1B, 0x61, n]; // ESC a n
  static List<int> _bold(bool on) => [0x1B, 0x45, on ? 1 : 0]; // ESC E n
  static List<int> _size(int n) => [0x1D, 0x21, n]; // GS ! n
  static const List<int> _feedAndCut = [0x1D, 0x56, 66, 0]; // GS V 66 0

  static Uint8List encode(
    KitchenTicket ticket, {
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

    // Header.
    bytes.addAll(_size(0x11)); // double width + height
    writeLine(
      ticket.isCopy ? 'MUTFAK FİŞİ (KOPYA)' : 'MUTFAK FİŞİ',
      bold: true,
      center: true,
    );
    bytes.addAll(_size(0x00));
    writeLine(ticket.header.channelLabel, center: true);
    if (ticket.header.tableLabel != null) {
      writeLine(ticket.header.tableLabel!, bold: true, center: true);
    }
    writeLine('Sipariş No: ${ticket.header.orderNumber}', center: true);
    writeLine(_formatDateTime(ticket.header.receivedAt), center: true);
    if (ticket.header.priority.isNotEmpty) {
      writeLine(ticket.header.priority, bold: true, center: true);
    }
    writeLine('-' * _lineWidth);

    // Lines — Ürün Adı/Adet, Siparişi Veren Kişi Adı, Reçete İçeriği,
    // Tercih Notları, in that order, for every line.
    for (final line in ticket.lines) {
      writeLine('${line.quantity} x ${line.productName}', bold: true);
      writeLine('  Sipariş Veren: ${line.orderedByName ?? "-"}');
      // Reçete içeriği/opsiyon satırları — mutfak personelinin eksiksiz
      // hazırlaması için ürünün altına girintili, "->" işaretli basılır
      // (2026-11-06 fiziksel çıktı testi). ASCII "->" deliberately, not a
      // Unicode arrow (→) — see `_encodeTurkish` below: anything outside
      // its override table prints as '?' on this printer.
      for (final ingredient in line.ingredientSummary) {
        writeLine('  -> $ingredient');
      }
      if (line.note.isNotEmpty) {
        writeLine('  -> Not: ${line.note}');
      }
      for (final warning in line.warnings) {
        writeLine('  ! $warning', bold: true);
      }
      writeLine('-' * _lineWidth);
    }

    writeLine('');
    bytes.addAll(_feedAndCut);
    return Uint8List.fromList(bytes);
  }

  static String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// Identical table/reasoning to `EscPosReceiptEncoder._encodeTurkish` —
  /// see that method's own doc comment.
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
