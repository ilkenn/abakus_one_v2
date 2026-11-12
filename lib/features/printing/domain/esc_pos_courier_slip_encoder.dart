import 'dart:typed_data';

import '../../pos/domain/delivery/courier_slip.dart';
import 'receipt_codepage.dart';
import 'turkish_ascii_transliteration.dart';

/// 2026-11-11 (Faz 2) — encodes a [CourierSlip] into the raw ESC/POS byte
/// stream for an 80mm thermal printer. Same primitives, codepage handling
/// and Turkish transliteration as `EscPosKitchenTicketEncoder` (kept
/// self-contained like every other encoder here). Layout: header, order
/// number and time, customer and full phone, address, a framed courier note,
/// items, delivery fee, a large total, the pay-on-delivery method and the
/// planned courier.
abstract final class EscPosCourierSlipEncoder {
  EscPosCourierSlipEncoder._();

  static const int _lineWidth = 48;

  static const List<int> _init = [0x1B, 0x40]; // ESC @
  static List<int> _selectCodepage(ReceiptCodepage codepage) =>
      [0x1B, 0x74, codepage == ReceiptCodepage.pc857 ? 19 : 45]; // ESC t n
  static List<int> _align(int n) => [0x1B, 0x61, n]; // ESC a n
  static List<int> _bold(bool on) => [0x1B, 0x45, on ? 1 : 0]; // ESC E n
  static List<int> _size(int n) => [0x1D, 0x21, n]; // GS ! n
  static const List<int> _feedAndCut = [0x1D, 0x56, 66, 0]; // GS V 66 0

  static Uint8List encode(
    CourierSlip slip, {
    ReceiptCodepage codepage = ReceiptCodepage.wpc1254,
  }) {
    final bytes = <int>[];
    bytes.addAll(_init);
    bytes.addAll(_selectCodepage(codepage));

    void writeLine(String text, {bool bold = false, bool center = false}) {
      bytes.addAll(_align(center ? 1 : 0));
      bytes.addAll(_bold(bold));
      bytes.addAll(_encode('$text\n', codepage));
      bytes.addAll(_bold(false));
      bytes.addAll(_align(0));
    }

    void writeTwoColumn(String left, String right, {bool bold = false}) {
      final space = _lineWidth - left.length - right.length;
      writeLine(
        space > 0 ? '$left${' ' * space}$right' : '$left $right',
        bold: bold,
      );
    }

    String money(int minorUnits) {
      final whole = minorUnits ~/ 100;
      final kurus = (minorUnits % 100).abs().toString().padLeft(2, '0');
      return '$whole,$kurus TL';
    }

    final rule = '-' * _lineWidth;

    bytes.addAll(_size(0x11));
    writeLine(slip.isCopy ? 'KURYE FİŞİ (KOPYA)' : 'KURYE FİŞİ',
        bold: true, center: true);
    bytes.addAll(_size(0x00));
    writeLine('${slip.restaurantName} - ${slip.branchName}', center: true);
    writeLine('Sipariş No: ${slip.orderNumber}', bold: true, center: true);
    writeLine(_formatDateTime(slip.createdAt), center: true);
    final eta = slip.estimatedDeliveryLine;
    if (eta != null) writeLine(eta, bold: true, center: true);
    writeLine(rule);

    writeLine('Müşteri: ${slip.customerName}', bold: true);
    writeLine('Telefon: ${slip.customerPhone}', bold: true);
    for (final line in slip.addressLines) {
      writeLine(line);
    }

    if (slip.courierNote.isNotEmpty) {
      writeLine('*' * _lineWidth);
      writeLine('KURYE NOTU: ${slip.courierNote}', bold: true);
      writeLine('*' * _lineWidth);
    }
    writeLine(rule);

    for (final line in slip.lines) {
      writeTwoColumn('${line.quantity} x ${line.productName}',
          money(line.lineTotalMinorUnits));
      for (final option in line.options) {
        writeLine('  + $option');
      }
    }
    writeLine(rule);
    if (slip.deliveryFeeMinorUnits > 0) {
      writeTwoColumn('Teslimat Ücreti', money(slip.deliveryFeeMinorUnits));
    }
    bytes.addAll(_size(0x11));
    writeTwoColumn('TOPLAM', money(slip.totalMinorUnits), bold: true);
    bytes.addAll(_size(0x00));
    writeLine('Ödeme: ${slip.paymentLabel}', bold: true);
    if (slip.plannedCourierName != null) {
      writeLine('Kurye: ${slip.plannedCourierName}');
    }
    writeLine('');
    bytes.addAll(_feedAndCut);
    return Uint8List.fromList(bytes);
  }

  static String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// ASCII-only after transliteration (see `turkish_ascii_transliteration
  /// .dart`); anything else prints as '?'.
  static List<int> _encode(String rawText, ReceiptCodepage codepage) {
    final text = transliterateTurkishToAscii(rawText);
    return [
      for (final rune in text.runes) rune <= 0x7F ? rune : 0x3F,
    ];
  }
}
