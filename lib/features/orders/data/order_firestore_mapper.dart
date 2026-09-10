import '../../../shared/models/courier_type.dart';
import '../../../shared/models/currency.dart';
import '../../../shared/models/money.dart';
import '../../payment/domain/models/payment_method_reporting_category.dart';
import '../../payment/domain/models/payment_method_snapshot.dart';
import '../../payment/domain/models/payment_provider_id.dart';
import '../../campaigns/domain/models/campaign.dart';
import '../domain/models/boncuk_redemption_snapshot.dart';
import '../domain/models/campaign_snapshot.dart';
import '../domain/models/catalog_reward_snapshot.dart';
import '../domain/models/courier_visibility.dart';
import '../domain/models/delivery_address_snapshot.dart';
import '../domain/models/order.dart';
import '../domain/models/order_actor.dart';
import '../domain/models/order_audit_entry.dart';
import '../domain/models/order_benefit_type.dart';
import '../domain/models/order_channel.dart';
import '../domain/models/order_id.dart';
import '../domain/models/dine_in_counter_proposal.dart';
import '../domain/models/dine_in_line_status.dart';
import '../domain/models/order_line.dart';
import '../domain/models/order_line_approval_state.dart';
import '../domain/models/order_line_modifier_selection.dart';
import '../domain/models/order_number.dart';
import '../domain/models/order_status.dart';
import '../domain/models/order_timestamps.dart';
import '../domain/models/pickup_mode.dart';
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
    final approvalStateByIndex = {
      for (final state in order.lineApprovalStates) state.lineIndex: state,
    };
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
      'guestAuthUid': order.guestAuthUid,
      'reservationContextId': order.reservationContextId,
      'takeawayEntrySessionId': order.takeawayEntrySessionId,
      'pickupMode': order.pickupMode?.name,
      'pickupTime': order.pickupTime?.toIso8601String(),
      // A raw DateTime (not a string) so the real `cloud_firestore` write
      // path stores this as a native Firestore Timestamp — Faz C. This is
      // the one field `firestore.rules`' `isValidAuthenticatedTakeawayOrder`
      // actually compares against `request.time` for the NOW+20 minimum
      // pickup-lead-time check; `request.time` is itself a `timestamp`
      // value and cannot be compared against the ISO-string `pickupTime`
      // field above (which stays a string, matching every other date field
      // on this document — `OrderTimestamps`' own fields included — so
      // display/parsing code has exactly one convention to follow). This
      // shadow field is write-only for rules' benefit: [fromFirestore]
      // deliberately never reads it back — it carries no information
      // `pickupTime` doesn't already have, it's just typed differently for
      // the one consumer (Security Rules) that needs a native Timestamp.
      'pickupTimeTimestamp': order.pickupTime,
      // AP-6 Sprint 1 — ISO-string, matching pickupTime's own convention;
      // same write-only native-Timestamp shadow-field pattern as
      // pickupTimeTimestamp above (`takeawayOperationsSweep.ts`'s candidate
      // query range-filters on this Timestamp field, never on the ISO
      // string — `functions/src/submitTakeawayOrder.ts`'s own
      // `buildOrderDocument` writes both together server-side). No real
      // client write path sets [Order.scheduledFor] today (only
      // `submitTakeawayOrder`/`takeawayOperationsSweep` ever do), but this
      // keeps the mapper's own write path complete rather than silently
      // divergent from the server's document shape.
      'scheduledFor': order.scheduledFor?.toIso8601String(),
      'scheduledForTimestamp': order.scheduledFor,
      'estimatedReadyAt': order.estimatedReadyAt?.toIso8601String(),
      // AP-6 Sprint 2 — no real client write path sets these today either
      // (only `assignCourierToOrder.ts` does); kept here for the same
      // "mapper's own write path stays complete" reasoning as scheduledFor
      // above.
      'assignedCourierId': order.assignedCourierId,
      'courierType': order.courierType?.name,
      'trackingToken': order.trackingToken,
      'contactFirstName': order.contactFirstName,
      'contactLastName': order.contactLastName,
      'contactPhone': order.contactPhone,
      'courierVisibility': order.courierVisibility.name,
      'lines': [
        for (var i = 0; i < order.lines.length; i++)
          _lineToFirestore(order.lines[i], approvalStateByIndex[i]),
      ],
      'pricing': _priceBreakdownToFirestore(order.pricing),
      'statusHistory': [
        for (final entry in order.statusHistory) _auditEntryToFirestore(entry),
      ],
      'version': order.version,
      'timestamps': _timestampsToFirestore(order.timestamps),
      'customerNote': order.customerNote,
      'kitchenNote': order.kitchenNote,
      'deliveryAddressSnapshot': order.deliveryAddressSnapshot == null
          ? null
          : _deliveryAddressSnapshotToFirestore(order.deliveryAddressSnapshot!),
      'paymentMethodSnapshot': order.paymentMethodSnapshot == null
          ? null
          : _paymentMethodSnapshotToFirestore(order.paymentMethodSnapshot!),
    };
  }

  static Order fromFirestore(Map<String, dynamic> data) {
    final rawLines = (data['lines'] as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList(growable: false);
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
      guestAuthUid: data['guestAuthUid'] as String?,
      reservationContextId: data['reservationContextId'] as String?,
      takeawayEntrySessionId: data['takeawayEntrySessionId'] as String?,
      pickupMode: _pickupModeFromName(data['pickupMode'] as String?),
      pickupTime: _parseNullableDateTime(data['pickupTime'] as String?),
      // AP-6 Sprint 1 — additive/nullable, same backward-compatibility
      // contract as boncukRedemption/catalogReward/campaign above: a
      // pre-AP-6 order document simply has no keys, both parse to null.
      scheduledFor: _parseNullableDateTime(data['scheduledFor'] as String?),
      estimatedReadyAt:
          _parseNullableDateTime(data['estimatedReadyAt'] as String?),
      // AP-6 Sprint 2 — same additive/nullable backward-compatibility
      // contract as scheduledFor/estimatedReadyAt above.
      assignedCourierId: data['assignedCourierId'] as String?,
      courierType: _courierTypeFromName(data['courierType'] as String?),
      trackingToken: data['trackingToken'] as String?,
      contactFirstName: data['contactFirstName'] as String?,
      contactLastName: data['contactLastName'] as String?,
      contactPhone: data['contactPhone'] as String?,
      courierVisibility:
          _courierVisibilityFromName(data['courierVisibility'] as String),
      lines: [for (final raw in rawLines) _lineFromFirestore(raw)],
      lineApprovalStates: [
        for (var i = 0; i < rawLines.length; i++)
          _lineApprovalStateFromFirestore(i, rawLines[i]),
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
      deliveryAddressSnapshot: data['deliveryAddressSnapshot'] == null
          ? null
          : _deliveryAddressSnapshotFromFirestore(Map<String, dynamic>.from(
              data['deliveryAddressSnapshot'] as Map)),
      paymentMethodSnapshot: data['paymentMethodSnapshot'] == null
          ? null
          : _paymentMethodSnapshotFromFirestore(
              Map<String, dynamic>.from(data['paymentMethodSnapshot'] as Map)),
      // Boncuk Loyalty P4-E-B (2026-08-22) — additive/nullable, same
      // backward-compatibility contract as deliveryAddressSnapshot/
      // paymentMethodSnapshot above: a pre-existing order document with
      // neither key present continues to parse exactly as it did before
      // this field existed (`orderBenefitTypeFromWire(null)` resolves to
      // `OrderBenefitType.none`, `boncukRedemption` stays `null`). A
      // PRESENT but malformed `boncukRedemption` map fails loudly via the
      // same `as`-cast-throws discipline every other required nested field
      // on this mapper already uses (`_moneyFromFirestore`, `_lineFromFirestore`,
      // ...) — never silently dropped or approximated.
      selectedBenefitType:
          orderBenefitTypeFromWire(data['selectedBenefitType'] as String?),
      boncukRedemption: data['boncukRedemption'] == null
          ? null
          : _boncukRedemptionSnapshotFromFirestore(
              Map<String, dynamic>.from(data['boncukRedemption'] as Map)),
      // Boncuk Loyalty P7-C (2026-08-24) — same additive/nullable
      // backward-compatibility contract as boncukRedemption above.
      catalogReward: data['catalogReward'] == null
          ? null
          : _catalogRewardSnapshotFromFirestore(
              Map<String, dynamic>.from(data['catalogReward'] as Map)),
      // Server-Authoritative Campaign Engine P8-C (2026-08-25) — same
      // additive/nullable backward-compatibility contract as
      // boncukRedemption/catalogReward above.
      campaign: data['campaign'] == null
          ? null
          : _campaignSnapshotFromFirestore(
              Map<String, dynamic>.from(data['campaign'] as Map)),
    );
  }

  static BoncukRedemptionSnapshot _boncukRedemptionSnapshotFromFirestore(
      Map<String, dynamic> data) {
    return BoncukRedemptionSnapshot(
      boncukUsed: data['boncukUsed'] as int,
      valueMinorUnits: data['valueMinorUnits'] as int,
      remainingPayableMinorUnits: data['remainingPayableMinorUnits'] as int,
      redemptionValueMinorUnitsPerBoncuk:
          data['redemptionValueMinorUnitsPerBoncuk'] as int,
      maxRedemptionBasisPoints: data['maxRedemptionBasisPoints'] as int,
      loyaltyPolicyVersion: data['loyaltyPolicyVersion'] as int,
    );
  }

  static CatalogRewardSnapshot _catalogRewardSnapshotFromFirestore(
      Map<String, dynamic> data) {
    return CatalogRewardSnapshot(
      rewardId: data['rewardId'] as String,
      rewardVersion: data['rewardVersion'] as int,
      title: data['title'] as String,
      boncukCost: data['boncukCost'] as int,
      redeemedProductId: data['redeemedProductId'] as String,
      redeemedQuantity: data['redeemedQuantity'] as int,
      coveredValueMinorUnits: data['coveredValueMinorUnits'] as int,
      rewardCatalogVersionId: data['rewardCatalogVersionId'] as String,
    );
  }

  static CampaignSnapshot _campaignSnapshotFromFirestore(
      Map<String, dynamic> data) {
    return CampaignSnapshot(
      campaignId: data['campaignId'] as String,
      campaignVersion: data['campaignVersion'] as int,
      title: data['title'] as String,
      campaignType: data['campaignType'] as String,
      appliedRule: CampaignRule.fromMap(
          Map<String, dynamic>.from(data['appliedRule'] as Map)),
      appliedValue: data['appliedValue'] as int,
      discountMinorUnits: data['discountMinorUnits'] as int,
      orderChannel: data['orderChannel'] as String,
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

  static Map<String, dynamic> _lineToFirestore(
    OrderLine line,
    OrderLineApprovalState? approvalState,
  ) =>
      {
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
        // AP-3 continuation — mirrors `functions/src/dineInCounterProposal
        // .ts`'s own raw shape: `status` embedded directly on each line map,
        // `counterProposal` alongside it, never a separate top-level array
        // on the wire (only [Order.lineApprovalStates] is separate, on the
        // Dart side only).
        'status': dineInLineStatusToWire(
          approvalState?.status ?? DineInLineStatus.accepted,
        ),
        'counterProposal': approvalState?.counterProposal == null
            ? null
            : _counterProposalToFirestore(approvalState!.counterProposal!),
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

  /// A raw line map with no `status` key at all (every non-dine-in-QR
  /// order, and every dine-in line that predates this feature) parses as
  /// [DineInLineStatus.accepted] with no [DineInCounterProposal] — the same
  /// backward-compatibility contract every other additive field on this
  /// mapper already follows.
  static OrderLineApprovalState _lineApprovalStateFromFirestore(
    int lineIndex,
    Map<String, dynamic> data,
  ) {
    return OrderLineApprovalState(
      lineIndex: lineIndex,
      status: dineInLineStatusFromWire(data['status'] as String?),
      counterProposal: data['counterProposal'] == null
          ? null
          : _counterProposalFromFirestore(
              Map<String, dynamic>.from(data['counterProposal'] as Map)),
    );
  }

  static Map<String, dynamic> _counterProposalToFirestore(
    DineInCounterProposal proposal,
  ) {
    return {
      'proposalVersion': proposal.proposalVersion,
      'proposedProductId': proposal.proposedProductId,
      'proposedProductName': proposal.proposedProductName,
      'proposedModifiers': [
        for (final modifier in proposal.proposedModifiers)
          {
            'groupId': modifier.groupId,
            'groupName': modifier.groupName,
            'optionId': modifier.optionId,
            'optionName': modifier.optionName,
            'unitExtraPrice': _moneyToFirestore(modifier.unitExtraPrice),
            'quantity': modifier.quantity,
          },
      ],
      'proposedQuantity': proposal.proposedQuantity,
      'proposedUnitPrice': _moneyToFirestore(proposal.proposedUnitPrice),
      'proposedLineTotalMinorUnits': proposal.proposedLineTotal.minorUnits,
      'differenceFromOriginalMinorUnits':
          proposal.differenceFromOriginal.minorUnits,
      'reasonCode': proposal.reasonCode,
      'reasonMessage': proposal.reasonMessage,
      'proposedByStaffUid': proposal.proposedByStaffUid,
      'createdAt': proposal.createdAt.toIso8601String(),
      'expiresAt': proposal.expiresAt.toIso8601String(),
      'status': switch (proposal.status) {
        DineInCounterProposalStatus.pending => 'pendingCustomerResponse',
        DineInCounterProposalStatus.accepted => 'accepted',
        DineInCounterProposalStatus.rejected => 'rejected',
        DineInCounterProposalStatus.expired => 'expired',
      },
      'respondedAt': proposal.respondedAt?.toIso8601String(),
    };
  }

  static DineInCounterProposal _counterProposalFromFirestore(
    Map<String, dynamic> data,
  ) {
    final unitPrice = _moneyFromFirestore(
        Map<String, dynamic>.from(data['proposedUnitPrice'] as Map));
    return DineInCounterProposal(
      proposalVersion: data['proposalVersion'] as int,
      proposedProductId: data['proposedProductId'] as String,
      proposedProductName: data['proposedProductName'] as String,
      proposedModifiers: [
        for (final raw in (data['proposedModifiers'] as List))
          _modifierFromFirestore(Map<String, dynamic>.from(raw as Map)),
      ],
      proposedQuantity: data['proposedQuantity'] as int,
      proposedUnitPrice: unitPrice,
      proposedLineTotal: Money(
        data['proposedLineTotalMinorUnits'] as int,
        unitPrice.currency,
      ),
      differenceFromOriginal: Money(
        data['differenceFromOriginalMinorUnits'] as int,
        unitPrice.currency,
      ),
      reasonCode: data['reasonCode'] as String,
      reasonMessage: data['reasonMessage'] as String,
      proposedByStaffUid: data['proposedByStaffUid'] as String,
      createdAt: DateTime.parse(data['createdAt'] as String),
      expiresAt: DateTime.parse(data['expiresAt'] as String),
      status: dineInCounterProposalStatusFromWire(data['status'] as String),
      respondedAt: data['respondedAt'] == null
          ? null
          : DateTime.parse(data['respondedAt'] as String),
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

  /// `null` for both a genuinely absent value and a pre-Faz-B document that
  /// has no `pickupMode` key at all — the same "missing key reads as no
  /// value" backward-compatibility every other additive nullable field on
  /// this mapper already relies on (see [fromFirestore]'s `String?` casts).
  static PickupMode? _pickupModeFromName(String? name) =>
      name == null ? null : PickupMode.values.byName(name);

  static CourierType? _courierTypeFromName(String? name) =>
      name == null ? null : CourierType.values.byName(name);

  static DateTime? _parseNullableDateTime(String? iso) =>
      iso == null ? null : DateTime.parse(iso);

  static Map<String, dynamic> _deliveryAddressSnapshotToFirestore(
      DeliveryAddressSnapshot snapshot) {
    return {
      'savedAddressId': snapshot.savedAddressId,
      'label': snapshot.label,
      'provinceId': snapshot.provinceId,
      'provinceName': snapshot.provinceName,
      'districtId': snapshot.districtId,
      'districtName': snapshot.districtName,
      'neighborhoodId': snapshot.neighborhoodId,
      'neighborhoodName': snapshot.neighborhoodName,
      'streetId': snapshot.streetId,
      'streetName': snapshot.streetName,
      'buildingNo': snapshot.buildingNo,
      'buildingNoSource': snapshot.buildingNoSource,
      'apartmentNo': snapshot.apartmentNo,
      'floor': snapshot.floor,
      'addressDescription': snapshot.addressDescription,
      'latitude': snapshot.latitude,
      'longitude': snapshot.longitude,
      'providerSource': snapshot.providerSource,
      'providerPlaceId': snapshot.providerPlaceId,
      'serverVerifiedAt': snapshot.serverVerifiedAt.toIso8601String(),
    };
  }

  static DeliveryAddressSnapshot _deliveryAddressSnapshotFromFirestore(
      Map<String, dynamic> data) {
    return DeliveryAddressSnapshot(
      savedAddressId: data['savedAddressId'] as String,
      label: data['label'] as String,
      provinceId: data['provinceId'] as String,
      provinceName: data['provinceName'] as String,
      districtId: data['districtId'] as String,
      districtName: data['districtName'] as String,
      neighborhoodId: data['neighborhoodId'] as String?,
      neighborhoodName: data['neighborhoodName'] as String?,
      streetId: data['streetId'] as String?,
      streetName: data['streetName'] as String?,
      buildingNo: data['buildingNo'] as String?,
      buildingNoSource: data['buildingNoSource'] as String?,
      apartmentNo: data['apartmentNo'] as String,
      floor: data['floor'] as String?,
      addressDescription: data['addressDescription'] as String?,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      providerSource: data['providerSource'] as String,
      providerPlaceId: data['providerPlaceId'] as String?,
      serverVerifiedAt: DateTime.parse(data['serverVerifiedAt'] as String),
    );
  }

  static Map<String, dynamic> _paymentMethodSnapshotToFirestore(
      PaymentMethodSnapshot snapshot) {
    return {
      'paymentMethodId': snapshot.paymentMethodId,
      'displayName': snapshot.displayName,
      'iconAssetPath': snapshot.iconAssetPath,
      'brandColorValue': snapshot.brandColorValue,
      'reportingCategory': snapshot.reportingCategory.name,
      'providerId': snapshot.providerId?.name,
      'supportsSplitPaymentAtCapture': snapshot.supportsSplitPaymentAtCapture,
      'supportsRefundAtCapture': snapshot.supportsRefundAtCapture,
      'requiresReferenceNumberAtCapture':
          snapshot.requiresReferenceNumberAtCapture,
      'requiresApprovalAtCapture': snapshot.requiresApprovalAtCapture,
      'transactionReference': snapshot.transactionReference,
      'authorizationCode': snapshot.authorizationCode,
      'terminalId': snapshot.terminalId,
    };
  }

  static PaymentMethodSnapshot _paymentMethodSnapshotFromFirestore(
      Map<String, dynamic> data) {
    return PaymentMethodSnapshot(
      paymentMethodId: data['paymentMethodId'] as String,
      displayName: data['displayName'] as String,
      iconAssetPath: data['iconAssetPath'] as String,
      brandColorValue: data['brandColorValue'] as int,
      reportingCategory: PaymentMethodReportingCategory.values
          .byName(data['reportingCategory'] as String),
      providerId: data['providerId'] == null
          ? null
          : PaymentProviderId.values.byName(data['providerId'] as String),
      supportsSplitPaymentAtCapture:
          data['supportsSplitPaymentAtCapture'] as bool,
      supportsRefundAtCapture: data['supportsRefundAtCapture'] as bool,
      requiresReferenceNumberAtCapture:
          data['requiresReferenceNumberAtCapture'] as bool,
      requiresApprovalAtCapture: data['requiresApprovalAtCapture'] as bool,
      transactionReference: data['transactionReference'] as String?,
      authorizationCode: data['authorizationCode'] as String?,
      terminalId: data['terminalId'] as String?,
    );
  }
}
