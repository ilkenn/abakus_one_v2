class MockZoneData {
  final String name;
  final double latitude;
  final double longitude;
  final List<String> streets;
  final List<String> buildings;

  const MockZoneData({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.streets,
    required this.buildings,
  });
}

class AddressDataRepository {
  static const Map<String, Map<String, MockZoneData>> hierarchy = {
    'K Kadıköy': {
      'Moda': MockZoneData(
        name: 'Moda',
        latitude: 40.9825,
        longitude: 29.0261,
        streets: ['Moda Caddesi', 'Şair Nefi Sokak', 'Badem Altı Sokak'],
        buildings: ['1', '3', '5', '12A', '24'],
      ),
      'Caferağa': MockZoneData(
        name: 'Caferağa',
        latitude: 40.9862,
        longitude: 29.0294,
        streets: ['Sakız Sokak', 'Nail Bey Sokak', 'Mühürdar Caddesi'],
        buildings: ['2', '4', '10', '18', '35'],
      ),
    },
    'Beşiktaş': {
      'Bebek': MockZoneData(
        name: 'Bebek',
        latitude: 41.0762,
        longitude: 29.0435,
        streets: ['Cevdet Paşa Caddesi', 'İnşirah Sokak', 'Bebek Yokuşu'],
        buildings: ['7', '9', '15', '42'],
      ),
    },
  };

  static List<String> getDistricts() => hierarchy.keys.toList();

  static List<String> getNeighborhoods(String district) {
    return hierarchy[district]?.keys.toList() ?? [];
  }

  static MockZoneData? getZoneDetails(String district, String neighborhood) {
    return hierarchy[district]?[neighborhood];
  }
}
