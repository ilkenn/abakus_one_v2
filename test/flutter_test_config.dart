import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

/// Runs once before every test in this suite. Disables `google_fonts`'
/// runtime network font-fetching (added 2026-10-29 for the customer
/// QR-ordering "Warm Artisanal & Craft" redesign — see
/// `lib/core/theme/qr_menu_theme.dart`) so widget tests that render
/// `QrMenuTypography` never attempt a real HTTP call: without this, every
/// such test would either hang on a sandboxed/offline test runner or, at
/// best, add real network latency to the suite. Tests still render with a
/// deterministic system-fallback text style, which is sufficient — these
/// tests assert on text content/structure, never on the exact rendered
/// font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
