import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/z_report_content.dart';
import 'package:abakus_one_v2/features/printing/domain/esc_pos_z_report_encoder.dart';
import 'package:abakus_one_v2/features/printing/domain/receipt_codepage.dart';

/// Adım 3 (2026-11-06) — mirrors `esc_pos_receipt_encoder_test.dart`'s own
/// byte-level verification reasoning: checks raw byte-sequence
/// containment, never a plain `latin1`/UTF-8 decode of the whole stream.
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

  ZReportContent buildContent({int complimentaryMinorUnits = 0}) {
    return ZReportContent(
      branchDisplayName: 'Abaküs Ortaköy',
      sessionId: 'sess-1',
      businessDate: '2026-11-06',
      openedAt: DateTime(2026, 11, 6, 9, 0),
      closedAt: DateTime(2026, 11, 6, 23, 0),
      currencySymbol: 'TL',
      openingFloatMinorUnits: 50000,
      cashMinorUnits: 100000,
      cardMinorUnits: 200000,
      otherMinorUnits: 5000,
      totalMinorUnits: 305000,
      expectedAmountMinorUnits: 150000,
      actualAmountMinorUnits: 150000,
      varianceType: 'exact',
      varianceAmountMinorUnits: 0,
      complimentaryMinorUnits: complimentaryMinorUnits,
    );
  }

  test(
      'varsayilan kodlama ESC t 45 (WPC1254) gonderir, codepage parametresi '
      'ESC t 19a (PC857) gecirir', () {
    final wpc1254Bytes = EscPosZReportEncoder.encode(buildContent());
    final pc857Bytes = EscPosZReportEncoder.encode(
      buildContent(),
      codepage: ReceiptCodepage.pc857,
    );

    expect(wpc1254Bytes.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 45]);
    expect(pc857Bytes.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 19]);
  });

  test('Z RAPORU basligi, sube adi ve toplam ciro ciktida gorunur', () {
    final bytes = EscPosZReportEncoder.encode(buildContent());

    expect(containsText(bytes, 'Z RAPORU'), isTrue);
    expect(containsText(bytes, 'Abaküs Ortaköy'), isTrue);
    expect(containsText(bytes, 'TOPLAM CİRO'), isTrue);
    expect(containsText(bytes, 'TL3050.00'), isTrue);
  });

  test('Ikram Toplami sifirdan farkliyken dogru tutarla basilir', () {
    final bytes = EscPosZReportEncoder.encode(
        buildContent(complimentaryMinorUnits: 2500));

    expect(containsText(bytes, 'İkram Toplamı'), isTrue);
    expect(containsText(bytes, 'TL25.00'), isTrue);
  });

  test('kasa farki (Fazla/Eksik/Tam) etiketiyle basilir', () {
    final shortContent = ZReportContent(
      branchDisplayName: 'Abaküs Ortaköy',
      sessionId: 'sess-1',
      businessDate: '2026-11-06',
      openedAt: DateTime(2026, 11, 6, 9, 0),
      closedAt: DateTime(2026, 11, 6, 23, 0),
      currencySymbol: 'TL',
      openingFloatMinorUnits: 0,
      cashMinorUnits: 0,
      cardMinorUnits: 0,
      otherMinorUnits: 0,
      totalMinorUnits: 0,
      expectedAmountMinorUnits: 10000,
      actualAmountMinorUnits: 9800,
      varianceType: 'short',
      varianceAmountMinorUnits: 200,
    );
    final bytes = EscPosZReportEncoder.encode(shortContent);

    expect(containsText(bytes, 'Kasa Farkı (Eksik)'), isTrue);
    expect(containsText(bytes, 'TL2.00'), isTrue);
  });
}

/// Mirrors `EscPosZReportEncoder._encodeTurkish`'s exact WPC1254 override
/// table — kept as a small, deliberate duplication, never importing the
/// private method itself.
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
