import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/printing/domain/esc_pos_receipt_encoder.dart';
import 'package:abakus_one_v2/features/printing/domain/receipt_codepage.dart';
import 'package:abakus_one_v2/features/printing/domain/receipt_document.dart';

/// 2026-11-06 physical print test fix — '₺' (U+20BA) has no slot in any
/// classic 8-bit ESC/POS codepage table, so it always printed as '?'
/// regardless of which table was selected. Proves `_formatAmount` now
/// prints 'TL' instead. Checks raw byte-sequence containment, mirroring
/// `esc_pos_kitchen_ticket_encoder_test.dart`'s own reasoning — a plain
/// `latin1`/UTF-8 decode of the whole stream doesn't round-trip the
/// encoder's Turkish-letter override table.
void main() {
  bool containsText(List<int> bytes, String text) {
    final needle = _encodeTurkishLikeEncoder(text);
    if (needle.isEmpty) return true;
    for (var i = 0; i <= bytes.length - needle.length; i++) {
      var matched = true;
      for (var j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }

  ReceiptDocument buildDoc({List<ReceiptLineItem>? lines}) {
    return ReceiptDocument(
      restaurantName: 'Abaküs',
      branchName: 'Ortaköy',
      tableName: '7',
      issuedAt: DateTime(2026, 11, 6, 19, 30),
      receiptNumber: 'R-1',
      lines: lines ??
          const [
            ReceiptLineItem(
              quantity: 2,
              productName: 'Tavuk Bowl',
              unitPriceMinorUnits: 15000,
              totalPriceMinorUnits: 30000,
            ),
          ],
      subtotalMinorUnits: 30000,
      discountMinorUnits: 0,
      totalMinorUnits: 30000,
      currencyCode: 'TRY',
    );
  }

  test(
      "TRY tutarlari '₺' sembolu degil 'TL' olarak basilir — sembol hicbir "
      'klasik kod sayfasinda yok, her zaman ? olarak cikiyordu', () {
    final bytes = EscPosReceiptEncoder.encode(buildDoc());

    expect(containsText(bytes, '300.00 TL'), isTrue);
  });

  test('TOPLAM satiri da TL ile basilir', () {
    final bytes = EscPosReceiptEncoder.encode(buildDoc());

    expect(containsText(bytes, 'TOPLAM'), isTrue);
    expect(containsText(bytes, '300.00 TL'), isTrue);
  });

  test(
      'varsayilan kodlama ESC t 45 (WPC1254) gonderir, codepage parametresi '
      'ESC t 19ya (PC857) gecirir — 2026-11-06 fiziksel self-test sonucu', () {
    final wpc1254Bytes = EscPosReceiptEncoder.encode(buildDoc());
    final pc857Bytes = EscPosReceiptEncoder.encode(
      buildDoc(),
      codepage: ReceiptCodepage.pc857,
    );

    // ESC @ (init) ardindan ESC t n: bayt dizisi [0x1B,0x40,0x1B,0x74,n].
    expect(wpc1254Bytes.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 45]);
    expect(pc857Bytes.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 19]);
  });

  test(
      'PC857 modunda Turkce harfler kendi dogrulanmis bayt degerleriyle '
      'basilir (iconv-lite cp857 ile dogrulandi, tahmin edilmedi)', () {
    final bytes = EscPosReceiptEncoder.encode(
      buildDoc(lines: const [
        ReceiptLineItem(
          quantity: 1,
          productName: 'Çılgın Şöhret Üçlü',
          unitPriceMinorUnits: 100,
          totalPriceMinorUnits: 100,
        ),
      ]),
      codepage: ReceiptCodepage.pc857,
    );

    bool containsBytes(List<int> needle) {
      for (var i = 0; i <= bytes.length - needle.length; i++) {
        var matched = true;
        for (var j = 0; j < needle.length; j++) {
          if (bytes[i + j] != needle[j]) {
            matched = false;
            break;
          }
        }
        if (matched) return true;
      }
      return false;
    }

    // Ç=0x80, ı=0x8D, Ş=0x9E, Ü=0x9A — "productName" alani Latin-1
    // passthrough DEGIL, PC857'nin kendi 0x80-0xFF duzenini kullanmali.
    expect(containsBytes([0x80]), isTrue); // Ç
    expect(containsBytes([0x8D]), isTrue); // ı
    expect(containsBytes([0x9E]), isTrue); // Ş
    expect(containsBytes([0x9A]), isTrue); // Ü
  });

  test('TRY disi bir para birimi kendi kodunu degismeden kullanir', () {
    final bytes = EscPosReceiptEncoder.encode(ReceiptDocument(
      restaurantName: 'Abaküs',
      branchName: 'Ortaköy',
      tableName: '7',
      issuedAt: DateTime(2026, 11, 6),
      receiptNumber: 'R-2',
      lines: const [
        ReceiptLineItem(
          quantity: 1,
          productName: 'Falafel Bowl',
          unitPriceMinorUnits: 10000,
          totalPriceMinorUnits: 10000,
        ),
      ],
      subtotalMinorUnits: 10000,
      discountMinorUnits: 0,
      totalMinorUnits: 10000,
      currencyCode: 'USD',
    ));

    expect(containsText(bytes, '100.00 USD'), isTrue);
  });
}

/// Mirrors `EscPosReceiptEncoder._encodeTurkish`'s exact override table —
/// kept as a small, deliberate duplication, never importing the private
/// method itself.
List<int> _encodeTurkishLikeEncoder(String text) {
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
      out.add(0x3F);
    }
  }
  return out;
}
