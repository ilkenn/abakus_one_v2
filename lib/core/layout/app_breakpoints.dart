/// Screen-width breakpoints, matching Material 3's compact/medium/expanded
/// window size classes.
///
/// Used to decide how many grid columns a content-heavy, image-forward
/// screen (Bowl Builder's ingredient picker) shows. Phones stay
/// single-column on purpose — Abaküs's customers are choosing food, and a
/// full-width photo sells a lot harder than a thumbnail. Tablets and wider
/// get more columns since there's room for it without shrinking photos down.
abstract final class AppBreakpoints {
  AppBreakpoints._();

  static const double tablet = 600.0;
  static const double desktop = 840.0;

  /// 1 column below [tablet], 2 between [tablet] and [desktop], 3 at
  /// [desktop] and above.
  static int columnsForWidth(double width) {
    if (width >= desktop) return 3;
    if (width >= tablet) return 2;
    return 1;
  }
}
