import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/qr_menu_theme.dart';

/// Resolves [QrMenuAmbientTint.forHour] exactly once per provider
/// lifetime (the device's local hour at first read), not on every widget
/// rebuild — a screen's `build()` only ever reads the cached value via
/// `ref.watch(qrMenuAmbientPaletteProvider)`. Deliberately not
/// `autoDispose`: the ambient tint is a once-per-session read, not
/// something that should flicker mid-visit if a screen is rebuilt for an
/// unrelated reason.
final qrMenuAmbientPaletteProvider = Provider<QrMenuAmbientPalette>((ref) {
  return QrMenuAmbientTint.forHour(DateTime.now().hour);
});
