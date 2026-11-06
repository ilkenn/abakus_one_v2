/// Which ESC/POS character-code table (`ESC t n`) and matching Turkish-
/// letter byte table a thermal-printer encoder should use. Configurable
/// because the correct one is firmware/vendor-specific and can only be
/// confirmed by a real physical print test — this printer's own self-test
/// page (2026-11-06) reported its default as CP437 (no Turkish support at
/// all) and gave the two real candidate tables below; neither index
/// matches the "standard" Epson TM-series numbering this codebase
/// originally assumed, confirming that assumption was never safe to rely
/// on for an unidentified clone printer.
///
/// Shared only as a selector value between `EscPosReceiptEncoder` and
/// `EscPosKitchenTicketEncoder` — each encoder still implements its own
/// `ESC t` byte/override table independently, matching this codebase's
/// existing "no shared encoding code between the two" design.
enum ReceiptCodepage {
  /// `ESC t 45` — Windows-1254. Full Turkish support (Ç/Ğ/İ/Ö/Ş/Ü and
  /// lowercase all present) — the default, tried first.
  wpc1254,

  /// `ESC t 19` — this printer's own self-test page reported this index
  /// for its PC857 (DOS Turkish) table. Fallback only, for a printer
  /// where [wpc1254] doesn't render correctly; byte values verified
  /// against a real CP857 codec (`iconv-lite`), not guessed.
  pc857,
}
