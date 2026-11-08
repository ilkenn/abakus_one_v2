/// ESC/POS Turkish-character fallback (2026-11-08) — physical-print
/// testing showed [ReceiptCodepage.wpc1254]'s `ESC t 45` selection (built
/// 2026-11-06, verified byte-correct against the real `windows-1254` codec)
/// still rendering Turkish letters wrong on the actual printer: ASCII-only
/// text (product notes/descriptions) printed fine, but the six Turkish
/// letters specifically did not — the signature of a printer that doesn't
/// actually honor the `ESC t` codepage-select command it was sent (common
/// on cheaper/clone 80mm thermal units) and silently stays on its own
/// default table regardless of what byte follows `ESC t`.
///
/// Rather than chase a third codepage guess with no way to verify it
/// against this unit short of another physical self-test, every receipt-
/// bound string is transliterated to plain ASCII FIRST, before it ever
/// reaches [EscPosReceiptEncoder]/[EscPosKitchenTicketEncoder]/
/// [EscPosZReportEncoder]'s own per-codepage byte tables — the standard,
/// hardware-independent way to make text print correctly on a printer
/// whose actual codepage behavior can't be fully trusted. Those per-
/// codepage tables are left in place, unused for Turkish letters now but
/// still exercised by anything ≤0xFF a future caller might send through
/// WPC1254 — this file does not reduce what they can do, it just means
/// they never see a non-ASCII Turkish letter to look up anymore.
///
/// Deliberately a plain nearest-ASCII-letter substitution
/// (ş→s, ğ→g, ı→i, ç→c, ö→o, ü→u, and their capitals), not a locale-aware
/// transform — a printed "Citir Tavuk" instead of "Çıtır Tavuk" is a
/// readable, honest degradation, never a corrupted/garbled character.
const Map<int, String> _turkishToAsciiTable = {
  0x00C7: 'C', // Ç
  0x00E7: 'c', // ç
  0x00D6: 'O', // Ö
  0x00F6: 'o', // ö
  0x00DC: 'U', // Ü
  0x00FC: 'u', // ü
  0x011E: 'G', // Ğ
  0x011F: 'g', // ğ
  0x0130: 'I', // İ
  0x0131: 'i', // ı
  0x015E: 'S', // Ş
  0x015F: 's', // ş
};

/// Replaces every Turkish letter in [text] with its nearest ASCII
/// equivalent; every other character (including already-ASCII text) is
/// left untouched.
String transliterateTurkishToAscii(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final replacement = _turkishToAsciiTable[rune];
    if (replacement != null) {
      buffer.write(replacement);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
