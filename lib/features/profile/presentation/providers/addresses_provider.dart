import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/address_model.dart';

class AddressesNotifier extends Notifier<List<AddressModel>> {
  @override
  List<AddressModel> build() {
    return const [
      AddressModel(
        id: 'addr_default_1',
        title: 'Ev',
        district: 'K Kadıköy',
        neighborhood: 'Moda',
        street: 'Moda Caddesi',
        buildingName: 'Abaküs Apartmanı',
        buildingNo: '12A',
        apartmentNo: '4',
        city: 'İstanbul',
        addressDescription: 'Zil sesine basınca kapıyı açın lütfen.',
        latitude: 40.9825,
        longitude: 29.0261,
        isDefault: true,
      ),
    ];
  }

  void addAddress(AddressModel address) {
    if (address.isDefault) {
      state = [
        for (final item in state) item.copyWith(isDefault: false),
        address,
      ];
    } else {
      state = [...state, address];
    }
  }

  void updateAddress(AddressModel updatedAddress) {
    state = [
      for (final item in state)
        if (item.id == updatedAddress.id)
          updatedAddress
        else if (updatedAddress.isDefault)
          item.copyWith(isDefault: false)
        else
          item,
    ];
  }

  void deleteAddress(String id) {
    state = state.where((item) => item.id != id).toList();
  }

  void setDefaultAddress(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(isDefault: true)
        else
          item.copyWith(isDefault: false),
    ];
  }
}

final addressesProvider =
    NotifierProvider<AddressesNotifier, List<AddressModel>>(() {
  return AddressesNotifier();
});
