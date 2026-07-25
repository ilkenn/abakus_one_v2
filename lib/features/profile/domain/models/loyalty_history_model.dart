class LoyaltyHistoryModel {
  final String id;
  final String title;
  final String date;
  final int points;
  final bool isEarned;

  const LoyaltyHistoryModel({
    required this.id,
    required this.title,
    required this.date,
    required this.points,
    required this.isEarned,
  });
}
