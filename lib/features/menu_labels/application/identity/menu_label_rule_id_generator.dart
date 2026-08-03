abstract interface class MenuLabelRuleIdGenerator {
  String nextMenuLabelRuleId();
}

class SequentialMenuLabelRuleIdGenerator implements MenuLabelRuleIdGenerator {
  SequentialMenuLabelRuleIdGenerator({this.prefix = 'menu-label-rule'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextMenuLabelRuleId() => '$prefix-${++_sequence}';
}
