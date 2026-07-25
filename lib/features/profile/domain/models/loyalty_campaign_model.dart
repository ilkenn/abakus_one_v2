/// One "Boncuk Kampanyaları" promotional card.
class LoyaltyCampaignModel {
  final String id;
  final String title;
  final String description;
  final String actionLabel;

  const LoyaltyCampaignModel({
    required this.id,
    required this.title,
    required this.description,
    required this.actionLabel,
  });
}
