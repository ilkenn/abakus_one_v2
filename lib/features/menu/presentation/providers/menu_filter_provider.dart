import 'package:flutter_riverpod/flutter_riverpod.dart';

class MenuFilterNotifier extends Notifier<String> {
  @override
  String build() {
    // Empty = no explicit pick yet; MenuScreen shows the first category.
    return '';
  }

  void setFilter(String filter) {
    state = filter;
  }
}

final menuFilterProvider = NotifierProvider<MenuFilterNotifier, String>(() {
  return MenuFilterNotifier();
});
