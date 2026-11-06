import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_header.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_line.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:abakus_one_v2/features/printing/domain/esc_pos_kitchen_ticket_encoder.dart';
import 'package:abakus_one_v2/features/printing/domain/receipt_codepage.dart';

/// Self-Order QR Faz 5 (23-rule plan §6) — proves the encoded ESC/POS byte
/// stream actually contains the 5 required per-line fields: Ürün Adı,
/// Adet, Siparişi Veren Kişi Adı, Reçete İçeriği, Tercih Notları.
///
/// Checks raw byte-sequence containment, never a plain `latin1`/UTF-8
/// decode of the whole stream — the encoder's own WPC1254 override table
/// maps the six Turkish-specific letters (ĞğİıŞş) to CP1254 byte values
/// that don't round-trip through `latin1.decode` (e.g. 'ş' -> 0xFE, which
/// `latin1` reads back as 'þ', not 'ş'). [_expectText] mirrors that exact
/// table so an assertion string written in real Turkish matches the real
/// encoded bytes.
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

  KitchenTicket buildTicket({List<KitchenTicketLine>? lines}) {
    return KitchenTicket(
      id: 'ticket-1',
      orderId: OrderId('order-1'),
      branchId: 'branch-1',
      type: KitchenTicketType.initial,
      header: KitchenTicketHeader(
        restaurantName: 'Abaküs',
        branchName: 'Ortaköy',
        channelLabel: 'Masa (QR)',
        orderNumber: 'DI-12345678',
        orderTypeLabel: 'Masa (QR)',
        receivedAt: DateTime(2026, 11, 5, 19, 30),
        tableLabel: 'Masa 7',
        channel: OrderChannel.dineInQr,
      ),
      lines: lines ??
          const [
            KitchenTicketLine(
              id: 'line-1',
              productName: 'Tavuk Bowl',
              quantity: 2,
              ingredientSummary: ['Karbonhidrat: Meksika Pilavı'],
              note: 'Az baharatlı olsun',
              orderedByName: 'Ahmet',
            ),
          ],
      firedAt: DateTime(2026, 11, 5, 19, 31),
      revision: 1,
    );
  }

  test(
      'tek satirlik biletin tum 5 zorunlu alani (Urun Adi, Adet, Siparisi '
      'Veren Kisi Adi, Recete Icerigi, Tercih Notlari) ciktida gorunur', () {
    final bytes = EscPosKitchenTicketEncoder.encode(buildTicket());

    expect(containsText(bytes, '2 x Tavuk Bowl'), isTrue); // Ürün Adı + Adet
    expect(containsText(bytes, 'Sipariş Veren: Ahmet'),
        isTrue); // Siparişi Veren Kişi Adı
    expect(containsText(bytes, 'Karbonhidrat: Meksika Pilavı'),
        isTrue); // Reçete İçeriği
    expect(containsText(bytes, 'Not: Az baharatlı olsun'),
        isTrue); // Tercih Notları
  });

  test('siparisi veren kisi bilinmiyorsa "-" ile gosterilir, bos birakilmaz',
      () {
    final bytes = EscPosKitchenTicketEncoder.encode(buildTicket(
      lines: const [
        KitchenTicketLine(
          id: 'line-1',
          productName: 'Falafel Bowl',
          quantity: 1,
        ),
      ],
    ));

    expect(containsText(bytes, 'Sipariş Veren: -'), isTrue);
  });

  test('bilet basligi masa etiketini ve siparis numarasini icerir', () {
    final bytes = EscPosKitchenTicketEncoder.encode(buildTicket());

    expect(containsText(bytes, 'Masa 7'), isTrue);
    expect(containsText(bytes, 'DI-12345678'), isTrue);
  });

  test('kopya bir bilet "MUTFAK FİŞİ (KOPYA)" basligi tasir', () {
    final ticket = buildTicket();
    final copy = ticket.copyWith(isCopy: true);
    final bytes = EscPosKitchenTicketEncoder.encode(copy);

    expect(containsText(bytes, 'KOPYA'), isTrue);
  });

  test(
      'recete icerigi ve tercih notlari girintili, "->" isaretiyle basilir '
      '(2026-11-06 fiziksel cikti testi)', () {
    final bytes = EscPosKitchenTicketEncoder.encode(buildTicket());

    expect(containsText(bytes, '  -> Karbonhidrat: Meksika Pilavı'), isTrue);
    expect(containsText(bytes, '  -> Not: Az baharatlı olsun'), isTrue);
  });

  test(
      'varsayilan kodlama ESC t 45 (WPC1254) gonderir, codepage parametresi '
      'ESC t 19ya (PC857) gecirir — 2026-11-06 fiziksel self-test sonucu', () {
    final wpc1254Bytes = EscPosKitchenTicketEncoder.encode(buildTicket());
    final pc857Bytes = EscPosKitchenTicketEncoder.encode(
      buildTicket(),
      codepage: ReceiptCodepage.pc857,
    );

    expect(wpc1254Bytes.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 45]);
    expect(pc857Bytes.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 19]);
  });

  test('birden fazla satir, her biri kendi 5 alanini ayri ayri yazdirir', () {
    final bytes = EscPosKitchenTicketEncoder.encode(buildTicket(
      lines: const [
        KitchenTicketLine(
          id: 'line-1',
          productName: 'Tavuk Bowl',
          quantity: 1,
          orderedByName: 'Ahmet',
        ),
        KitchenTicketLine(
          id: 'line-2',
          productName: 'Falafel Bowl',
          quantity: 3,
          orderedByName: 'Ayşe',
        ),
      ],
    ));

    expect(containsText(bytes, '1 x Tavuk Bowl'), isTrue);
    expect(containsText(bytes, 'Sipariş Veren: Ahmet'), isTrue);
    expect(containsText(bytes, '3 x Falafel Bowl'), isTrue);
    expect(containsText(bytes, 'Sipariş Veren: Ayşe'), isTrue);
  });
}

/// Mirrors `EscPosKitchenTicketEncoder._encodeTurkish`'s exact override
/// table — kept as a small, deliberate duplication (this is precisely what
/// the test is verifying), never importing the private method itself.
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
