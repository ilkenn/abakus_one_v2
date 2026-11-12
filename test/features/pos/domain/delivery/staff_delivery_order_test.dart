import 'dart:convert';

import 'package:abakus_one_v2/features/orders/data/order_firestore_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/delivery_address_snapshot.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line_modifier_selection.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_reporting_category.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/features/pos/domain/delivery/courier_slip.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_mapper.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:abakus_one_v2/features/printing/domain/esc_pos_courier_slip_encoder.dart';
import 'package:abakus_one_v2/features/printing/domain/esc_pos_kitchen_ticket_encoder.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_new_takeaway_order_screen.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-11 (Faz 2) — a staff-opened Paket Servis order as the server
/// writes it: typed address (no coordinates), courier note, kitchen note,
/// planned courier, pay-on-delivery Multinet, 30 TL delivery fee.
Order _deliveryOrder() {
  final line = OrderLine.create(
    productId: 'p1',
    productName: 'Tavuk Bowl',
    modifiers: [
      OrderLineModifierSelection(
        groupId: 'g1',
        groupName: 'Ekstra',
        optionId: 'o1',
        optionName: 'Ekstra Peynir',
        unitExtraPrice: Money.fromWhole(55, Currency.tryLira),
        quantity: 1,
      ),
    ],
    quantity: 1,
    unitPrice: Money.fromWhole(610, Currency.tryLira),
    taxRate: TaxPolicy.defaultRate,
    customerNote: 'Sosu ayrı olsun',
  );
  return Order(
    id: OrderId('delivery-1'),
    orderNumber: OrderNumber('DL-ABCD1234'),
    status: OrderStatus.confirmed,
    channel: OrderChannel.delivery,
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
    contactFirstName: 'Ayşe',
    contactLastName: 'Demir',
    contactPhone: '+905321112233',
    plannedCourierId: 'courier-2',
    plannedCourierName: 'Mehmet',
    customerNote: 'Zile basmayın',
    kitchenNote: 'Et orta-iyi pişsin',
    lines: [line],
    pricing: PriceCalculator.calculate(
      lines: [line],
      currency: Currency.tryLira,
      deliveryFee: Money.fromWhole(30, Currency.tryLira),
    ),
    timestamps: OrderTimestamps(created: DateTime(2026, 11, 11, 19, 30)),
    deliveryAddressSnapshot: const DeliveryAddressSnapshot(
      savedAddressId: 'org-1_hash',
      label: '',
      provinceId: '',
      provinceName: '',
      districtId: '',
      districtName: '',
      neighborhoodName: 'Caferağa',
      streetName: 'Moda Caddesi',
      buildingNo: '12',
      apartmentNo: '4',
      addressDescription: 'Eczanenin üstü',
      latitude: null,
      longitude: null,
      providerSource: 'staffManual',
      serverVerifiedAt: null,
    ),
    paymentMethodSnapshot: const PaymentMethodSnapshot(
      paymentMethodId: 'multinet',
      displayName: 'Multinet',
      iconAssetPath: 'assets/images/payment/multinet.png',
      brandColorValue: 0xfff37021,
      reportingCategory: PaymentMethodReportingCategory.mealCard,
      supportsSplitPaymentAtCapture: true,
      supportsRefundAtCapture: true,
      requiresReferenceNumberAtCapture: false,
      requiresApprovalAtCapture: false,
    ),
  );
}

String _ascii(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

void main() {
  group('courier slip', () {
    test('built from the server order: phone, address, note, total, payment',
        () {
      final slip = CourierSlip.fromOrder(
        order: _deliveryOrder(),
        restaurantName: 'Abaküs',
        branchName: 'Merkez Şube',
      );
      expect(slip.customerName, 'Ayşe Demir');
      expect(slip.customerPhone, '+905321112233');
      expect(slip.addressLines, [
        'Caferağa, Moda Caddesi',
        'No 12 / Daire 4',
        'Tarif: Eczanenin üstü',
      ]);
      expect(slip.courierNote, 'Zile basmayın');
      expect(slip.lines.single.options, ['Ekstra Peynir']);
      expect(slip.lines.single.lineTotalMinorUnits, 66500, reason: '610 + 55');
      expect(slip.deliveryFeeMinorUnits, 3000);
      expect(slip.totalMinorUnits, 69500);
      expect(slip.paymentLabel, 'Kapıda Yemek Kartı (Multinet)');
      expect(slip.plannedCourierName, 'Mehmet');
    });

    test('pay-on-delivery labels', () {
      expect(CourierSlip.paymentLabelFor('cash', 'Nakit'), 'Kapıda Nakit');
      expect(CourierSlip.paymentLabelFor('credit_card', 'Kredi Kartı'),
          'Kapıda POS');
      expect(CourierSlip.paymentLabelFor('edenred', 'Edenred'),
          'Kapıda Yemek Kartı (Edenred)');
    });

    test('the printed slip carries every field (ASCII-transliterated)', () {
      final text = _ascii(EscPosCourierSlipEncoder.encode(
        CourierSlip.fromOrder(
          order: _deliveryOrder(),
          restaurantName: 'Abaküs',
          branchName: 'Merkez Şube',
          isCopy: true,
        ),
      ));
      for (final expected in [
        'KURYE FISI (KOPYA)',
        'DL-ABCD1234',
        'Musteri: Ayse Demir',
        'Telefon: +905321112233',
        'Caferaga, Moda Caddesi',
        'KURYE NOTU: Zile basmayin',
        '1 x Tavuk Bowl',
        '+ Ekstra Peynir',
        'Teslimat Ucreti',
        '695,00 TL',
        'Odeme: Kapida Yemek Karti (Multinet)',
        'Kurye: Mehmet',
      ]) {
        expect(text, contains(expected), reason: expected);
      }
    });
  });

  group('kitchen notes', () {
    test(
        'the order-level kitchen note and the line note typed by staff both '
        'reach the kitchen ticket', () {
      final ticket = KitchenTicketMapper.fromOrder(
        ticketId: 'kt-1',
        order: _deliveryOrder(),
        type: KitchenTicketType.initial,
        restaurantName: 'Abaküs',
        branchName: 'Merkez Şube',
        firedAt: DateTime(2026, 11, 11, 19, 30),
      );
      expect(ticket.header.orderNote, 'Et orta-iyi pişsin');
      expect(ticket.lines.single.note, 'Sosu ayrı olsun');

      final printed = _ascii(EscPosKitchenTicketEncoder.encode(ticket));
      expect(printed, contains('MUTFAK NOTU: Et orta-iyi pissin'));
      expect(printed, contains('Not: Sosu ayri olsun'));
    });
  });

  group('order mapping', () {
    test('a staff-typed address without coordinates round-trips', () {
      final order = _deliveryOrder();
      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      final address = data['deliveryAddressSnapshot'] as Map<String, dynamic>;
      expect(address['latitude'], isNull);
      expect(address['serverVerifiedAt'], isNull);
      expect(data['plannedCourierId'], 'courier-2');

      final back = OrderFirestoreMapper.fromFirestore(data);
      expect(back.deliveryAddressSnapshot!.latitude, isNull);
      expect(back.deliveryAddressSnapshot!.providerSource, 'staffManual');
      expect(back.plannedCourierName, 'Mehmet');
      expect(back.customerNote, 'Zile basmayın');
      expect(back.kitchenNote, 'Et orta-iyi pişsin');
    });
  });

  group('normalizeTurkishPhoneForPos', () {
    test('mirrors the server: typed shapes → E.164, others refused', () {
      for (final raw in ['0532 111 22 33', '5321112233', '+90 532 111 22 33']) {
        expect(normalizeTurkishPhoneForPos(raw), '+905321112233', reason: raw);
      }
      expect(normalizeTurkishPhoneForPos('12345'), isNull);
      expect(normalizeTurkishPhoneForPos('0132 111 22 33'), isNull);
    });
  });
}
