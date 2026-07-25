class RestaurantStatusModel {
  final bool isOpen;
  final String openingTime;
  final String closingTime;
  final int estimatedDeliveryMinutes;
  final bool isBusy;
  final bool acceptsOrders;
  final String statusMessage;

  const RestaurantStatusModel({
    required this.isOpen,
    required this.openingTime,
    required this.closingTime,
    required this.estimatedDeliveryMinutes,
    required this.isBusy,
    required this.acceptsOrders,
    required this.statusMessage,
  });
}
