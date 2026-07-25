import 'package:flutter_riverpod/flutter_riverpod.dart';

class MenuFilterNotifier extends Notifier<String> {
  @override
  String build() {
    return 'Tümü';
  }

  void setFilter(String filter) {
    state = filter;
  }
}

final menuFilterProvider = NotifierProvider<MenuFilterNotifier, String>(() {
  return MenuFilterNotifier();
});
