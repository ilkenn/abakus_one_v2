import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One entry per persistent bottom-navigation destination. `slug` is the
/// stable identifier this tab will be addressed by once deep links
/// (`abakus://menu`, `abakus://cart`, ...) are wired up — chosen now so
/// [NavigationNotifier.selectTab]/[NavigationNotifier.selectTabBySlug] don't
/// need to change shape when that lands. QR order is deliberately not a
/// tab here: it's a one-shot scan action pushed on top of whatever's
/// currently showing, not a persistent destination.
enum AppTab {
  home('home'),
  menu('menu'),
  buildBowl('build-bowl'),
  cart('cart'),
  profile('profile');

  final String slug;

  const AppTab(this.slug);

  static AppTab? fromSlug(String slug) {
    for (final tab in values) {
      if (tab.slug == slug) return tab;
    }
    return null;
  }
}

class NavigationNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void selectTab(AppTab tab) {
    state = tab;
  }

  /// Future deep-link entry point (`abakus://menu` etc.) — nothing calls
  /// this yet, no deep-link parser is wired up. Kept so that parser has a
  /// single, already-correct method to call rather than needing its own
  /// slug-to-tab mapping. Returns `false` for an unrecognized slug instead
  /// of throwing, so a malformed/unknown link can't crash the app.
  bool selectTabBySlug(String slug) {
    final tab = AppTab.fromSlug(slug);
    if (tab == null) return false;
    state = tab;
    return true;
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, AppTab>(() {
  return NavigationNotifier();
});
