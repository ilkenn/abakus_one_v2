class AddressModel {
  final String id;
  final String title;
  final String neighborhood;
  final String street;
  final String buildingName;
  final String buildingNo;
  final String apartmentNo;
  final String district;
  final String city;
  final String addressDescription;
  final double latitude;
  final double longitude;
  final bool isDefault;

  const AddressModel({
    required this.id,
    required this.title,
    required this.neighborhood,
    required this.street,
    required this.buildingName,
    required this.buildingNo,
    required this.apartmentNo,
    required this.district,
    required this.city,
    required this.addressDescription,
    required this.latitude,
    required this.longitude,
    this.isDefault = false,
  });

  AddressModel copyWith({
    String? id,
    String? title,
    String? neighborhood,
    String? street,
    String? buildingName,
    String? buildingNo,
    String? apartmentNo,
    String? district,
    String? city,
    String? addressDescription,
    double? latitude,
    double? longitude,
    bool? isDefault,
  }) {
    return AddressModel(
      id: id ?? this.id,
      title: title ?? this.title,
      neighborhood: neighborhood ?? this.neighborhood,
      street: street ?? this.street,
      buildingName: buildingName ?? this.buildingName,
      buildingNo: buildingNo ?? this.buildingNo,
      apartmentNo: apartmentNo ?? this.apartmentNo,
      district: district ?? this.district,
      city: city ?? this.city,
      addressDescription: addressDescription ?? this.addressDescription,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
