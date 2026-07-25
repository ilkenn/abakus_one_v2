enum CampaignType { percentage, amount, freeDelivery, loyalty }

class CampaignModel {
  final String id;
  final String title;
  final String description;
  final String endDate;
  final CampaignType campaignType;
  final String couponCode;
  final double minimumOrderAmount;
  final double discountValue;
  final bool isActive;
  final bool isClaimed;

  const CampaignModel({
    required this.id,
    required this.title,
    required this.description,
    required this.endDate,
    required this.campaignType,
    required this.couponCode,
    required this.minimumOrderAmount,
    required this.discountValue,
    required this.isActive,
    required this.isClaimed,
  });

  CampaignModel copyWith({
    String? id,
    String? title,
    String? description,
    String? endDate,
    CampaignType? campaignType,
    String? couponCode,
    double? minimumOrderAmount,
    double? discountValue,
    bool? isActive,
    bool? isClaimed,
  }) {
    return CampaignModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      endDate: endDate ?? this.endDate,
      campaignType: campaignType ?? this.campaignType,
      couponCode: couponCode ?? this.couponCode,
      minimumOrderAmount: minimumOrderAmount ?? this.minimumOrderAmount,
      discountValue: discountValue ?? this.discountValue,
      isActive: isActive ?? this.isActive,
      isClaimed: isClaimed ?? this.isClaimed,
    );
  }
}
