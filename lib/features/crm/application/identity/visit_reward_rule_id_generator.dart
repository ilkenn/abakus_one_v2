abstract interface class VisitRewardRuleIdGenerator {
  String nextRuleId();
}

class SequentialVisitRewardRuleIdGenerator
    implements VisitRewardRuleIdGenerator {
  SequentialVisitRewardRuleIdGenerator({this.prefix = 'reward-rule'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextRuleId() => '$prefix-${++_sequence}';
}
