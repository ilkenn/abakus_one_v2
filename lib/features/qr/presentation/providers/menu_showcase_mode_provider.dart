import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_table_context_provider.dart';

/// 2026-11-09 — whether the app was opened through the read-only "vitrin"
/// menu (`AppRoutes.menuShowcase`, the floor-stand QR at the entrance).
/// Set by `MenuShowcaseScreen`; never persisted — a page reload or a table
/// QR link starts fresh.
class MenuShowcaseModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() => state = true;

  void exit() => state = false;
}

final menuShowcaseModeProvider =
    NotifierProvider<MenuShowcaseModeNotifier, bool>(
  MenuShowcaseModeNotifier.new,
);

/// The effective restriction: showcase mode AND no table yet. Scanning a
/// table's QR sets [activeTableContextProvider], which lifts the
/// restriction immediately even if the showcase flag were still set.
final isMenuShowcaseActiveProvider = Provider<bool>((ref) {
  return ref.watch(menuShowcaseModeProvider) &&
      ref.watch(activeTableContextProvider) == null;
});
