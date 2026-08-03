abstract interface class MenuCategoryIdGenerator {
  String nextMenuCategoryId();
}

class SequentialMenuCategoryIdGenerator implements MenuCategoryIdGenerator {
  SequentialMenuCategoryIdGenerator({this.prefix = 'menu-category'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextMenuCategoryId() => '$prefix-${++_sequence}';
}
