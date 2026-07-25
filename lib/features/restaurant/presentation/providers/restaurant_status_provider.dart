import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/restaurant_status_model.dart';

class RestaurantStatusNotifier extends Notifier<RestaurantStatusModel> {
  @override
  RestaurantStatusModel build() {
    // Test ve sunum amacıyla varsayılan olarak açık ancak yoğun bir mock senaryo kurulmuştur.
    return const RestaurantStatusModel(
      isOpen: true,
      openingTime: '09:00',
      closingTime: '22:00',
      estimatedDeliveryMinutes: 45,
      isBusy: true,
      acceptsOrders: true,
      statusMessage:
          'Şu an yoğunluk sebebiyle teslimat süreleri biraz uzayabilir.',
    );
  }

  void updateStatus({
    bool? isOpen,
    int? estimatedDeliveryMinutes,
    bool? isBusy,
    bool? acceptsOrders,
    String? statusMessage,
  }) {
    state = RestaurantStatusModel(
      isOpen: isOpen ?? state.isOpen,
      openingTime: state.openingTime,
      closingTime: state.closingTime,
      estimatedDeliveryMinutes:
          estimatedDeliveryMinutes ?? state.estimatedDeliveryMinutes,
      isBusy: isBusy ?? state.isBusy,
      acceptsOrders: acceptsOrders ?? state.acceptsOrders,
      statusMessage: statusMessage ?? state.statusMessage,
    );
  }
}

final restaurantStatusProvider =
    NotifierProvider<RestaurantStatusNotifier, RestaurantStatusModel>(() {
  return RestaurantStatusNotifier();
});
