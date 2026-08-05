import '../../../shared/models/currency.dart';
import '../../../shared/models/money.dart';
import '../domain/models/courier_visibility.dart';
import '../domain/models/order.dart';
import '../domain/models/order_actor.dart';
import '../domain/models/order_audit_entry.dart';
import '../domain/models/order_channel.dart';
import '../domain/models/order_id.dart';
import '../domain/models/order_line.dart';
import '../domain/models/order_line_modifier_selection.dart';
import '../domain/models/order_number.dart';
import '../domain/models/order_status.dart';
import '../domain/models/order_timestamps.dart';
import '../domain/pricing/price_breakdown.dart';
import '../domain/pricing/tax_rate.dart';

/// Converts a canonical [Order] to/from the Firestore document shape
/// `firestore.rules`'/`docs/firestore_data_model.md`'s `orders` collection
/// defines — Sprint 9E (`docs/decisions.md` ADR-026). Kept as a standalone
/// mapper (not methods on [Order] itself) for the same reason
/// `CartToOrderMapper`/`CartLineMapper` are standalone: [Order] stays free
/// of any storage-format concern, per this app's "domain entities and
/// API/DTO shapes are not required to be identical" rule (`CLAUDE.md` §4).
///
/// [OrderLine] cannot be reconstructed with pre-computed derived fields —
/// its constructor is private; only [OrderLine.create] is public, and it
/// *recomputes* `modifierTotal`/`lineSubtotal`/`lineTotal`/`tax` from raw
/// inputs. [toFirestore] therefore stores only those raw inputs per line
/// (`productId`, `productName`, `modifiers`, `quantity`, `unitPrice`,
/// `lineDiscount`, `tax.rate`, notes); [fromFirestore] replays
/// [OrderLine.create] with them — a pure, deterministic function of its
/// inputs, so this reproduces the exact original frozen line, not an
/// approximation. [PriceBreakdown] has a normal public constructor, so its
/// fields round-trip directly with no recomputation needed.
abstract final class OrderFirestoreMapper {
  OrderFirestoreMapper._();

  /// [organizationId] is not a field on [Order] itself — Sprint 9B's
  /// tenant model denormalizes it onto every tenant document at write
  /// time (`docs/firestore_data_model.md`); the caller (
  /// [FirestoreCanonicalOrderRepository]) resolves it via the
  /// restaurant→organization chain before calling this.
  static Map<String, dynamic> toFirestore(
    Order order, {
    required String organizationId,
  }) {
    return {
      'organizationId': organizationId,
      'orderId': order.id.value,
      'orderNumber': order.orderNumber.value,
      'status': order.status.name,
      'channel': order.channel.name,
      'branchId': order.branchId,
      'restaurantId': order.restaurantId,
      'customerId': order.customerId,
      'tableId': order.tableId,
      'tableSessionId': order.tableSessionId,
      'guestSessionId': order.guestSessionId,
      'courierVisibility': order.courierVisibility.name,
      'lines': [for (final line in order.lines) _lineToFirestore(line)],
      'pricing': _priceBreakdownToFirestore(order.pricing),
      'statusHistory': [
        for (final entry in order.statusHistory) _auditEntryToFirestore(entry),
      ],
      'version': order.version,
      'timestamps': _timestampsToFirestore(order.timestamps),
      'customerNote': order.customerNote,
      'kitchenNote': order.kitchenNote,
    };
  }

  static Order fromFirestore(Map<String, dynamic> data) {
    return Order(
      id: OrderId(data['orderId'] as String),
      orderNumber: OrderNumber(data['orderNumber'] as String),
      status: _statusFromName(data['status'] as String),
      channel: _channelFromName(data['channel'] as String),
      branchId: data['branchId'] as String,
      restaurantId: data['restaurantId'] as String,
      customerId: data['customerId'] as String?,
      tableId: data['tableId'] as String?,
      tableSessionId: data['tableSessionId'] as String?,
      guestSessionId: data['guestSessionId'] as String?,
      courierVisibility:
          _courierVisibilityFromName(data['courierVisibility'] as String),
      lines: [
        for (final raw in (data['lines'] as List))
          _lineFromFirestore(Map<String, dynamic>.from(raw as Map)),
      ],
      pricing: _priceBreakdownFromFirestore(
          Map<String, dynamic>.from(data['pricing'] as Map)),
      statusHistory: [
        for (final raw in (data['statusHistory'] as List))
          _auditEntryFromFirestore(Map<String, dynamic>.from(raw as Map)),
      ],
      version: data['version'] as int,
      timestamps: _timestampsFromFirestore(
          Map<String, dynamic>.from(data['timestamps'] as Map)),
      customerNote: data['customerNote'] as String? ?? '',
      kitchenNote: data['kitchenNote'] as String? ?? '',
    );
  }

  static Map<String, dynamic> _moneyToFirestore(Money money) => {
        'minorUnits': money.minorUnits,
        'currencyCode': money.currency.isoCode,
      };

  static Money _moneyFromFirestore(Map<String, dynamic> data) {
    final code = data['currencyCode'] as String;
    final currency = Currency.all.firstWhere(
      (c) => c.isoCode == code,
      orElse: () => throw StateError('Unknown currency code "$code"'),
    );
    return Money(data['minorUnits'] as int, currency);
  }

  static Map<String, dynamic> _lineToFirestore(OrderLine line) => {
        'productId': line.productId,
        'productName': line.productName,
        'modifiers': [
          for (final modifier in line.modifiers)
            {
              'groupId': modifier.groupId,
              'groupName': modifier.groupName,
              'optionId': modifier.optionId,
              'optionName': modifier.optionName,
              'unitExtraPrice': _moneyToFirestore(modifier.unitExtraPrice),
              'quantity': modifier.quantity,
            },
        ],
        'quantity': line.quantity,
        'unitPrice': _moneyToFirestore(line.unitPrice),
        'lineDiscount': _moneyToFirestore(line.lineDiscount),
        'taxRateBasisPoints': line.tax.rate.basisPoints,
        'kitchenNote': line.kitchenNote,
        'customerNote': line.customerNote,
      };

  static OrderLine _lineFromFirestore(Map<String, dynamic> data) {
    return OrderLine.create(
      productId: data['productId'] as String,
      productName: data['productName'] as String,
      modifiers: [
        for (final raw in (data['modifiers'] as List))
          _modifierFromFirestore(Map<String, dynamic>.from(raw as Map)),
      ],
      quantity: data['quantity'] as int,
      unitPrice: _moneyFromFirestore(
          Map<String, dynamic>.from(data['unitPrice'] as Map)),
      lineDiscount: _moneyFromFirestore(
          Map<String, dynamic>.from(data['lineDiscount'] as Map)),
      taxRate: TaxRate.fromBasisPoints(data['taxRateBasisPoints'] as int),
      kitchenNote: data['kitchenNote'] as String? ?? '',
      customerNote: data['customerNote'] as String? ?? '',
    );
  }

  static OrderLineModifierSelection _modifierFromFirestore(
      Map<String, dynamic> data) {
    return OrderLineModifierSelection(
      groupId: data['groupId'] as String,
      groupName: data['groupName'] as String,
      optionId: data['optionId'] as String,
      optionName: data['optionName'] as String,
      unitExtraPrice: _moneyFromFirestore(
          Map<String, dynamic>.from(data['unitExtraPrice'] as Map)),
      quantity: data['quantity'] as int,
    );
  }

  static Map<String, dynamic> _priceBreakdownToFirestore(
      PriceBreakdown pricing) {
    return {
      'grossSubtotal': _moneyToFirestore(pricing.grossSubtotal),
      'discount': _moneyToFirestore(pricing.discount),
      'taxableBase': _moneyToFirestore(pricing.taxableBase),
      'vatAmount': _moneyToFirestore(pricing.vatAmount),
      'serviceFee': _moneyToFirestore(pricing.serviceFee),
      'deliveryFee': _moneyToFirestore(pricing.deliveryFee),
      'packagingFee': _moneyToFirestore(pricing.packagingFee),
      'tip': _moneyToFirestore(pricing.tip),
      'grandTotal': _moneyToFirestore(pricing.grandTotal),
    };
  }

  static PriceBreakdown _priceBreakdownFromFirestore(
      Map<String, dynamic> data) {
    Money field(String key) =>
        _moneyFromFirestore(Map<String, dynamic>.from(data[key] as Map));
    return PriceBreakdown(
      grossSubtotal: field('grossSubtotal'),
      discount: field('discount'),
      taxableBase: field('taxableBase'),
      vatAmount: field('vatAmount'),
      serviceFee: field('serviceFee'),
      deliveryFee: field('deliveryFee'),
      packagingFee: field('packagingFee'),
      tip: field('tip'),
      grandTotal: field('grandTotal'),
    );
  }

  static Map<String, dynamic> _auditEntryToFirestore(OrderAuditEntry entry) {
    return {
      'id': entry.id,
      'type': entry.type.name,
      'description': entry.description,
      'actor': entry.actor.name,
      'timestamp': entry.timestamp.toIso8601String(),
      'previousValue': entry.previousValue,
      'newValue': entry.newValue,
    };
  }

  static OrderAuditEntry _auditEntryFromFirestore(Map<String, dynamic> data) {
    return OrderAuditEntry(
      id: data['id'] as String,
      type: OrderAuditChangeType.values.byName(data['type'] as String),
      description: data['description'] as String,
      actor: OrderActor.values.byName(data['actor'] as String),
      timestamp: DateTime.parse(data['timestamp'] as String),
      previousValue: data['previousValue'] as String?,
      newValue: data['newValue'] as String?,
    );
  }

  static Map<String, dynamic> _timestampsToFirestore(OrderTimestamps ts) {
    String? iso(DateTime? value) => value?.toIso8601String();
    return {
      'created': iso(ts.created),
      'confirmed': iso(ts.confirmed),
      'preparing': iso(ts.preparing),
      'ready': iso(ts.ready),
      'served': iso(ts.served),
      'completed': iso(ts.completed),
      'cancelled': iso(ts.cancelled),
    };
  }

  static OrderTimestamps _timestampsFromFirestore(Map<String, dynamic> data) {
    DateTime? parse(String key) {
      final raw = data[key] as String?;
      return raw == null ? null : DateTime.parse(raw);
    }

    return OrderTimestamps(
      created: DateTime.parse(data['created'] as String),
      confirmed: parse('confirmed'),
      preparing: parse('preparing'),
      ready: parse('ready'),
      served: parse('served'),
      completed: parse('completed'),
      cancelled: parse('cancelled'),
    );
  }

  static OrderStatus _statusFromName(String name) =>
      OrderStatus.values.byName(name);

  static OrderChannel _channelFromName(String name) =>
      OrderChannel.values.byName(name);

  static CourierVisibility _courierVisibilityFromName(String name) =>
      CourierVisibility.values.byName(name);
}
