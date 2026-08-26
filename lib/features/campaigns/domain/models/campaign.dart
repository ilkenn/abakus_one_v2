/// Server-Authoritative Campaign Engine P8-B (2026-08-25) — the real
/// customer-facing Campaign model, sourced exclusively from
/// `getCustomerActiveCampaigns` (`CampaignGateway`). Replaces the old
/// `CampaignModel` (`campaignsProvider`'s previous 4 hardcoded fake
/// campaigns with `ABAKUS10`/`ILKSIPARIS`/`UCRETSIZ`/`YAZBITTI` coupon
/// codes) entirely — there is no local/mock campaign source anywhere in
/// this feature anymore.
///
/// `campaignType`/`rule.mechanic`/`rule.scope.kind`/`schedule.mode` are
/// deliberately opaque strings, never a Dart enum — mirrors
/// `LoyaltyReward.rewardType`'s own established "never hardcode the
/// vocabulary client-side" rule (`BR-LOYALTY-028`), since the server alone
/// owns the closed set of valid values.
library;

class Campaign {
  const Campaign({
    required this.campaignId,
    required this.title,
    required this.description,
    required this.campaignType,
    required this.rule,
    required this.eligibleChannels,
    required this.eligibleProductIds,
    required this.eligibleCategoryIds,
    required this.minimumBasketMinorUnits,
    required this.schedule,
    required this.sortOrder,
    required this.version,
  });

  final String campaignId;
  final String title;
  final String description;
  final String campaignType;
  final CampaignRule rule;
  final List<String> eligibleChannels;
  final List<String>? eligibleProductIds;
  final List<String>? eligibleCategoryIds;
  final int? minimumBasketMinorUnits;
  final CampaignSchedule schedule;
  final int sortOrder;
  final int version;

  bool isEligibleForChannel(String channel) =>
      eligibleChannels.contains(channel);
}

/// The one shared internal engine every `campaignType` maps onto, mirrored
/// verbatim from `functions/src/campaignEngine.ts`'s own `CampaignRule`
/// union — a flat, nullable-field DTO (not a Dart sealed hierarchy),
/// matching this codebase's existing convention for server-driven
/// discriminated data (`LoyaltyReward` itself has no sealed variant either).
class CampaignRule {
  const CampaignRule({
    required this.mechanic,
    this.scopeKind,
    this.scopeProductId,
    this.scopeCategoryId,
    this.percentBasisPoints,
    this.amountMinorUnits,
    this.freeProductId,
    this.triggerProductId,
    this.triggerQuantity,
    this.rewardProductId,
    this.rewardQuantity,
  });

  /// `"percentage" | "fixedAmount" | "freeProduct" | "buyXGetY"`.
  final String mechanic;

  /// Only present when [mechanic] is `"percentage"`/`"fixedAmount"` —
  /// `"order" | "product" | "category"`.
  final String? scopeKind;
  final String? scopeProductId;
  final String? scopeCategoryId;

  /// Only present when [mechanic] is `"percentage"` — basis points (10000 = 100%).
  final int? percentBasisPoints;

  /// Only present when [mechanic] is `"fixedAmount"` — minor units (kuruş).
  final int? amountMinorUnits;

  /// Only present when [mechanic] is `"freeProduct"`.
  final String? freeProductId;

  /// Only present when [mechanic] is `"buyXGetY"`.
  final String? triggerProductId;
  final int? triggerQuantity;
  final String? rewardProductId;
  final int? rewardQuantity;

  /// Parses a raw `rule` map — shared by [CampaignGateway] (the customer
  /// campaign list) and, from Server-Authoritative Campaign Engine P8-C
  /// (2026-08-25) onward, `OrderFirestoreMapper` (an order's frozen
  /// `campaign.appliedRule` snapshot) — both sourced from the exact same
  /// backend `CampaignRule` shape
  /// (`functions/src/campaignEngine.ts`), so one parser serves both call
  /// sites rather than two near-duplicates drifting apart.
  factory CampaignRule.fromMap(Map<String, dynamic> data) {
    final mechanic = data['mechanic'];
    if (mechanic is! String) {
      throw FormatException(
          'CampaignRule: mechanic must be a string, got ${mechanic.runtimeType}');
    }
    final scopeRaw = data['scope'];
    final scope = scopeRaw is Map ? Map<String, dynamic>.from(scopeRaw) : null;
    int? asInt(dynamic value) => value == null ? null : (value as num).toInt();

    return CampaignRule(
      mechanic: mechanic,
      scopeKind: scope?['kind'] as String?,
      scopeProductId: scope?['productId'] as String?,
      scopeCategoryId: scope?['categoryId'] as String?,
      percentBasisPoints: asInt(data['percentBasisPoints']),
      amountMinorUnits: asInt(data['amountMinorUnits']),
      freeProductId: data['freeProductId'] as String?,
      triggerProductId: data['triggerProductId'] as String?,
      triggerQuantity: asInt(data['triggerQuantity']),
      rewardProductId: data['rewardProductId'] as String?,
      rewardQuantity: asInt(data['rewardQuantity']),
    );
  }
}

class CampaignSchedule {
  const CampaignSchedule({
    required this.mode,
    this.startAt,
    this.endAt,
    this.recurringWindows,
  });

  /// `"oneTime" | "recurring"`.
  final String mode;

  /// Only present when [mode] is `"oneTime"`.
  final DateTime? startAt;
  final DateTime? endAt;

  /// Only present when [mode] is `"recurring"`.
  final List<CampaignRecurringWindow>? recurringWindows;
}

class CampaignRecurringWindow {
  const CampaignRecurringWindow({
    required this.weekdays,
    required this.startMinute,
    required this.endMinute,
  });

  /// `0 = Sunday .. 6 = Saturday`, matching `DateTime.weekday`'s own
  /// `1 = Monday .. 7 = Sunday` convention is NOT used here — this mirrors
  /// the server's own `Date.prototype.getDay()` convention exactly, so no
  /// translation is needed when comparing against a value the server
  /// itself later confirms server-side.
  final List<int> weekdays;
  final int startMinute;
  final int endMinute;
}
