abstract interface class MenuLabelSuggestionIdGenerator {
  String nextMenuLabelSuggestionId();
}

class SequentialMenuLabelSuggestionIdGenerator
    implements MenuLabelSuggestionIdGenerator {
  SequentialMenuLabelSuggestionIdGenerator({
    this.prefix = 'menu-label-suggestion',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextMenuLabelSuggestionId() => '$prefix-${++_sequence}';
}
