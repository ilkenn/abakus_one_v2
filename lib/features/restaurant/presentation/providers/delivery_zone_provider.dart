import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../profile/domain/models/address_model.dart';
import '../../domain/models/delivery_zone_model.dart';

class DeliveryZoneNotifier extends Notifier<List<DeliveryZoneModel>> {
  @override
  List<DeliveryZoneModel> build() {
    // Mock veriler, profile_provider/addresses içerisindeki olası mahalle test senaryolarına göre eşleştirilmiştir.
    return const [
      DeliveryZoneModel(
        id: 'zone_1',
        name: 'Merkez Bölgesi',
        district:
            'K Kadıköy', // Mevcut mock datalardaki isimlendirme formatına uyum sağlanmıştır
        neighborhood: 'Moda',
        minimumOrderAmount: 200.0,
        deliveryFee: 29.0,
        estimatedDeliveryMinutes: 35,
        isActive: true,
      ),
      DeliveryZoneModel(
        id: 'zone_2',
        name: 'Geçici Kapalı Bölge',
        district: 'Kadıköy',
        neighborhood: 'Acıbadem',
        minimumOrderAmount: 300.0,
        deliveryFee: 49.0,
        estimatedDeliveryMinutes: 50,
        isActive: false,
      ),
    ];
  }

  String checkEligibility(AddressModel? address) {
    if (address == null) return 'Adres Seçilmedi';

    final zones = state;
    final match = zones.firstWhere(
      (z) =>
          z.district.toLowerCase().trim() ==
              address.district.toLowerCase().trim() &&
          z.neighborhood.toLowerCase().trim() ==
              address.neighborhood.toLowerCase().trim(),
      orElse: () => const DeliveryZoneModel(
        id: '',
        name: '',
        district: '',
        neighborhood: '',
        minimumOrderAmount: 0,
        deliveryFee: 0,
        estimatedDeliveryMinutes: 0,
        isActive: false,
      ),
    );

    if (match.id.isEmpty) {
      return 'Bölge Dışı';
    }
    if (!match.isActive) {
      return 'Geçici Olarak Kapalı';
    }
    return 'Teslimat Yapılabilir';
  }

  DeliveryZoneModel? getZoneByAddress(AddressModel? address) {
    if (address == null) return null;
    try {
      return state.firstWhere(
        (z) =>
            z.district.toLowerCase().trim() ==
                address.district.toLowerCase().trim() &&
            z.neighborhood.toLowerCase().trim() ==
                address.neighborhood.toLowerCase().trim(),
      );
    } catch (_) {
      return null;
    }
  }
}

final deliveryZoneProvider =
    NotifierProvider<DeliveryZoneNotifier, List<DeliveryZoneModel>>(() {
  return DeliveryZoneNotifier();
});
