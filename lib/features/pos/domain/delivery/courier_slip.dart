import '../../../orders/domain/models/order.dart';

/// One product line on a courier slip.
class CourierSlipLine {
  const CourierSlipLine({
    required this.quantity,
    required this.productName,
    required this.options,
    required this.lineTotalMinorUnits,
  });

  final int quantity;
  final String productName;

  /// Chosen modifier names ("Ekstra Peynir").
  final List<String> options;
  final int lineTotalMinorUnits;
}

/// 2026-11-11 (Faz 2) — what the courier slip shows, built from the
/// server-written delivery [Order] only (never from local cart state, so the
/// printed prices are the server's): order number and time, the customer's
/// name and FULL phone, the address and directions, the courier note
/// (highlighted), the items, the delivery fee, the total, the
/// pay-on-delivery method ("Kapıda Nakit — 450,00 TL") and the planned
/// courier.
class CourierSlip {
  const CourierSlip({
    required this.restaurantName,
    required this.branchName,
    required this.orderNumber,
    required this.createdAt,
    required this.customerName,
    required this.customerPhone,
    required this.addressLines,
    required this.courierNote,
    required this.lines,
    required this.deliveryFeeMinorUnits,
    required this.totalMinorUnits,
    required this.paymentLabel,
    required this.plannedCourierName,
    this.isCopy = false,
  });

  final String restaurantName;
  final String branchName;
  final String orderNumber;
  final DateTime createdAt;
  final String customerName;
  final String customerPhone;
  final List<String> addressLines;
  final String courierNote;
  final List<CourierSlipLine> lines;
  final int deliveryFeeMinorUnits;
  final int totalMinorUnits;

  /// "Kapıda Nakit", "Kapıda POS", "Kapıda Yemek Kartı (Multinet)".
  final String paymentLabel;
  final String? plannedCourierName;
  final bool isCopy;

  /// Pay-on-delivery label for a `paymentMethodSnapshot.paymentMethodId`.
  static String paymentLabelFor(String? paymentMethodId, String? displayName) {
    return switch (paymentMethodId) {
      'cash' => 'Kapıda Nakit',
      'credit_card' => 'Kapıda POS',
      null => 'Ödeme yöntemi belirtilmedi',
      _ => 'Kapıda Yemek Kartı (${displayName ?? paymentMethodId})',
    };
  }

  static CourierSlip fromOrder({
    required Order order,
    required String restaurantName,
    required String branchName,
    bool isCopy = false,
  }) {
    final address = order.deliveryAddressSnapshot;
    final addressLines = <String>[
      if (address != null) ...[
        [
          address.neighborhoodName,
          address.streetName,
        ].whereType<String>().where((p) => p.isNotEmpty).join(', '),
        [
          if ((address.buildingNo ?? '').isNotEmpty) 'No ${address.buildingNo}',
          if (address.apartmentNo.isNotEmpty) 'Daire ${address.apartmentNo}',
          if ((address.floor ?? '').isNotEmpty) 'Kat ${address.floor}',
        ].join(' / '),
        if ((address.addressDescription ?? '').isNotEmpty)
          'Tarif: ${address.addressDescription}',
      ],
    ].where((line) => line.trim().isNotEmpty).toList();
    final name = [order.contactFirstName, order.contactLastName]
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .join(' ');
    return CourierSlip(
      restaurantName: restaurantName,
      branchName: branchName,
      orderNumber: order.orderNumber.value,
      createdAt: order.timestamps.created,
      customerName: name.isEmpty ? '-' : name,
      customerPhone: order.contactPhone ?? '-',
      addressLines: addressLines,
      courierNote: order.customerNote.trim(),
      lines: [
        for (final line in order.lines)
          CourierSlipLine(
            quantity: line.quantity,
            productName: line.productName,
            options: [for (final m in line.modifiers) m.optionName],
            lineTotalMinorUnits: line.lineTotal.minorUnits,
          ),
      ],
      deliveryFeeMinorUnits: order.pricing.deliveryFee.minorUnits,
      totalMinorUnits: order.pricing.grandTotal.minorUnits,
      paymentLabel: paymentLabelFor(
        order.paymentMethodSnapshot?.paymentMethodId,
        order.paymentMethodSnapshot?.displayName,
      ),
      plannedCourierName: order.plannedCourierName,
      isCopy: isCopy,
    );
  }
}
