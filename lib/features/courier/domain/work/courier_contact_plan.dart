import 'courier_work_models.dart';

/// ADR-085 stage 4 — where an order came from, as far as calling goes.
enum CourierOrderSource {
  own,
  yemeksepeti,
  trendyol,
  getir;

  static CourierOrderSource parse(String? value) => switch (value) {
        'yemeksepeti' => yemeksepeti,
        'trendyol' => trendyol,
        'getir' => getir,
        _ => own,
      };

  /// Trendyol and Getir hide the customer's number: the courier calls the
  /// platform's restaurant line and keys the order code.
  bool get usesSwitchboard => this == trendyol || this == getir;

  String get label => switch (this) {
        own => 'Abaküs',
        yemeksepeti => 'Yemeksepeti',
        trendyol => 'Trendyol',
        getir => 'Getir',
      };
}

/// The courier's "Ara" button: what it dials and what it says.
class CourierCallPlan {
  const CourierCallPlan({required this.uri, required this.label});
  final Uri uri;
  final String label;
}

String _dialDigits(String value) => value.replaceAll(RegExp(r'[^0-9+]'), '');

/// `null` when there is nothing to call (delivered — KVKK — or no number).
///
/// Own orders and Yemeksepeti: the customer (`tel:<phone>`). Trendyol and
/// Getir: the configured switchboard, then a pause and the order code ended
/// with `#`, dialled automatically (`tel:02123653403,,<code>%23` — `#` must
/// be URL-encoded or the dialer drops everything after it).
CourierCallPlan? courierCallPlan(CourierWorkOrder order) {
  if (order.status == CourierWorkOrderStatus.deliveredAwaitingSettlement) {
    return null;
  }
  if (order.source.usesSwitchboard) {
    final switchboard = _dialDigits(order.switchboardPhone ?? '');
    if (switchboard.isEmpty) return null;
    final code = (order.marketplaceOrderCode ?? '').replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return CourierCallPlan(
      uri: Uri.parse(
        code.isEmpty ? 'tel:$switchboard' : 'tel:$switchboard,,$code%23',
      ),
      label: '${order.source.label} Santrali Ara',
    );
  }
  final phone = _dialDigits(order.customerPhone ?? '');
  if (phone.isEmpty) return null;
  return CourierCallPlan(
    uri: Uri(scheme: 'tel', path: phone),
    label: 'Müşteriyi Ara',
  );
}

/// One way to open the destination in a navigation app.
class CourierNavigationOption {
  const CourierNavigationOption({required this.label, required this.uri});
  final String label;
  final Uri uri;
}

/// "Konuma Git": Google Maps, Apple Maps and Yandex — to the address pin
/// when the order has one, otherwise to the written address. Empty when
/// delivered (KVKK) or there is nothing to navigate to.
List<CourierNavigationOption> courierNavigationOptions(
  CourierWorkOrder order,
) {
  if (order.status == CourierWorkOrderStatus.deliveredAwaitingSettlement) {
    return const [];
  }
  final lat = order.destinationLatitude;
  final lng = order.destinationLongitude;
  if (lat != null && lng != null) {
    final point = '$lat,$lng';
    return [
      CourierNavigationOption(
        label: 'Google Haritalar',
        uri: Uri.https('www.google.com', '/maps/dir/', {
          'api': '1',
          'destination': point,
        }),
      ),
      CourierNavigationOption(
        label: 'Apple Haritalar',
        uri: Uri.https('maps.apple.com', '/', {'daddr': point}),
      ),
      CourierNavigationOption(
        label: 'Yandex Haritalar',
        uri: Uri.https('yandex.com.tr', '/harita/', {
          'rtext': '~$point',
          'rtt': 'auto',
        }),
      ),
    ];
  }
  final address = [order.addressLine, order.neighborhoodName]
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join(', ');
  if (address.isEmpty) return const [];
  return [
    CourierNavigationOption(
      label: 'Google Haritalar',
      uri: Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': address,
      }),
    ),
    CourierNavigationOption(
      label: 'Apple Haritalar',
      uri: Uri.https('maps.apple.com', '/', {'daddr': address}),
    ),
    CourierNavigationOption(
      label: 'Yandex Haritalar',
      uri: Uri.https('yandex.com.tr', '/harita/', {'text': address}),
    ),
  ];
}
