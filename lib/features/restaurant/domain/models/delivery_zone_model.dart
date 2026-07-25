class DeliveryZoneModel {
  final String id;
  final String name;
  final String district;
  final String neighborhood;
  final double minimumOrderAmount;
  final double deliveryFee;
  final int estimatedDeliveryMinutes;
  final bool isActive;

  const DeliveryZoneModel({
    required this.id,
    required this.name,
    required this.district,
    required this.neighborhood,
    required this.minimumOrderAmount,
    required this.deliveryFee,
    required this.estimatedDeliveryMinutes,
    required this.isActive,
  });
}
