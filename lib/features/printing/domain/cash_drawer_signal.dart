/// ESC/POS cash-drawer "kick" pulse — Adım 4 (2026-11-07), "Para Çekmecesi
/// Entegrasyonu". The drawer is wired through the receipt printer's own
/// RJ11/RJ12 port, not a separate device, so this byte sequence is sent to
/// the SAME configured printer queue as the till receipt
/// (`ReceiptPrinterSettings.printerName`), never a distinct connection.
///
/// `ESC p 0 25 250` (`0x1B, 0x70, 0x00, 0x19, 0xFA`) — the exact bytes the
/// operator's own hardware notes specified; kept as a literal constant
/// exactly as given, not re-derived from ESC/POS's general pulse-timing
/// formula.
const List<int> kCashDrawerKickBytes = [0x1B, 0x70, 0x00, 0x19, 0xFA];
