/// A redeemable reward in the "Boncuklarını Harca" catalog.
class LoyaltyRewardModel {
  final String id;
  final String title;
  final String description;
  final int cost;

  const LoyaltyRewardModel({
    required this.id,
    required this.title,
    required this.description,
    required this.cost,
  });
}
