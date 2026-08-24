import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../../../core/services/logging/log_level.dart';
import '../../../core/services/logging/logging_provider.dart';
import '../../../core/services/logging/logging_service.dart';
import '../domain/models/loyalty_account_snapshot.dart';
import '../domain/models/loyalty_history_entry.dart';
import '../domain/models/loyalty_reward.dart';

class LoyaltyGatewayException implements Exception {
  const LoyaltyGatewayException(this.code, this.message);

  /// A `FirebaseFunctionsException.code` value, or `'parse-error'`/
  /// `'unknown'` for a non-`FirebaseFunctionsException` failure. Callers
  /// branch on this, never on [message]'s text.
  final String code;
  final String message;

  @override
  String toString() => 'LoyaltyGatewayException($code): $message';
}

/// P3A (2026-08-23) — the customer-side bridge to
/// `functions/src/getCustomerLoyaltySnapshot.ts` and
/// `functions/src/getCustomerLoyaltyHistory.ts`. Mirrors
/// `CustomerRegistrationGateway`'s exact discipline: never sends
/// `organizationId`/`customerId`/`uid` — both callables resolve identity
/// exclusively server-side.
abstract interface class LoyaltyGateway {
  Future<LoyaltyAccountSnapshot> getSnapshot();

  Future<LoyaltyHistoryPage> getHistory({int? pageSize, String? cursor});

  /// Boncuk Loyalty Program P7-B/P7-C (2026-08-24) — the bridge to
  /// `functions/src/getCustomerLoyaltyRewardCatalog.ts`. Returns only
  /// currently active/non-archived/currently-valid rewards for the
  /// caller's own tenant, already sorted by `sortOrder` — the server's own
  /// contract, never re-filtered/re-sorted client-side.
  Future<List<LoyaltyReward>> getRewardCatalog();
}

/// Parses `getCustomerLoyaltySnapshot`'s decoded response — a pure,
/// top-level function (not inlined), mirroring
/// `parseCompleteCustomerProfileResult`'s established discipline: never
/// assume a wire value's Dart runtime type without checking it explicitly.
LoyaltyAccountSnapshot parseLoyaltySnapshot(Map<String, dynamic> data) {
  int requireIntField(
      Map<String, dynamic> source, String field, String context) {
    final value = source[field];
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw FormatException(
      '$context: $field must be a number, got ${value.runtimeType}',
    );
  }

  int requireInt(String field) =>
      requireIntField(data, field, 'getCustomerLoyaltySnapshot response');

  // Configurable Loyalty Economics (2026-08-24) — the server-authoritative
  // policy is a required nested object, never optional/defaulted here: a
  // missing/malformed policy must surface as a parse failure (honest
  // retry state), never a silently-fabricated rate.
  final policyRaw = data['policy'];
  if (policyRaw is! Map) {
    throw FormatException(
      'getCustomerLoyaltySnapshot response: policy must be an object, '
      'got ${policyRaw.runtimeType}',
    );
  }
  final policy = Map<String, dynamic>.from(policyRaw);
  int requirePolicyInt(String field) => requireIntField(
        policy,
        field,
        'getCustomerLoyaltySnapshot response.policy',
      );

  return LoyaltyAccountSnapshot(
    spendableBalance: requireInt('spendableBalance'),
    boncukDebt: requireInt('boncukDebt'),
    earningRemainderMinorUnits: requireInt('earningRemainderMinorUnits'),
    minorUnitsUntilNextBoncuk: requireInt('minorUnitsUntilNextBoncuk'),
    lifetimeEarned: requireInt('lifetimeEarned'),
    lifetimeRedeemed: requireInt('lifetimeRedeemed'),
    earningSpendMinorUnits: requirePolicyInt('earningSpendMinorUnits'),
    earningBoncukAmount: requirePolicyInt('earningBoncukAmount'),
    redemptionValueMinorUnitsPerBoncuk:
        requirePolicyInt('redemptionValueMinorUnitsPerBoncuk'),
    maxRedemptionBasisPoints: requirePolicyInt('maxRedemptionBasisPoints'),
  );
}

LoyaltyHistoryEntry _parseHistoryEntry(Map<String, dynamic> data) {
  final eventId = data['eventId'];
  if (eventId is! String) {
    throw FormatException(
      'getCustomerLoyaltyHistory response: eventId must be a string, '
      'got ${eventId.runtimeType}',
    );
  }
  final type = data['type'];
  if (type is! String) {
    throw FormatException(
      'getCustomerLoyaltyHistory response: type must be a string, '
      'got ${type.runtimeType}',
    );
  }
  final displayBoncukDelta = data['displayBoncukDelta'];
  if (displayBoncukDelta is! num) {
    throw FormatException(
      'getCustomerLoyaltyHistory response: displayBoncukDelta must be a '
      'number, got ${displayBoncukDelta.runtimeType}',
    );
  }
  final debtAppliedBoncuk = data['debtAppliedBoncuk'];
  if (debtAppliedBoncuk is! num) {
    throw FormatException(
      'getCustomerLoyaltyHistory response: debtAppliedBoncuk must be a '
      'number, got ${debtAppliedBoncuk.runtimeType}',
    );
  }
  final occurredAtRaw = data['occurredAt'];
  final occurredAt =
      occurredAtRaw is String ? DateTime.tryParse(occurredAtRaw) : null;
  if (occurredAt == null) {
    throw FormatException(
      'getCustomerLoyaltyHistory response: occurredAt must be a valid ISO '
      '8601 timestamp string, got $occurredAtRaw',
    );
  }
  final orderId = data['orderId'];
  if (orderId != null && orderId is! String) {
    throw FormatException(
      'getCustomerLoyaltyHistory response: orderId must be a string when '
      'present, got ${orderId.runtimeType}',
    );
  }

  return LoyaltyHistoryEntry(
    eventId: eventId,
    type: loyaltyLedgerEntryTypeFromWire(type),
    displayBoncukDelta: displayBoncukDelta.toInt(),
    debtAppliedBoncuk: debtAppliedBoncuk.toInt(),
    occurredAt: occurredAt,
    orderId: orderId as String?,
  );
}

/// Parses `getCustomerLoyaltyHistory`'s decoded response.
LoyaltyHistoryPage parseLoyaltyHistoryPage(Map<String, dynamic> data) {
  final rows = data['rows'];
  if (rows is! List) {
    throw FormatException(
      'getCustomerLoyaltyHistory response: rows must be a list, '
      'got ${rows.runtimeType}',
    );
  }
  final entries = rows
      .map((row) => _parseHistoryEntry(Map<String, dynamic>.from(row as Map)))
      .toList(growable: false);

  final nextCursor = data['nextCursor'];
  if (nextCursor != null && nextCursor is! String) {
    throw FormatException(
      'getCustomerLoyaltyHistory response: nextCursor must be a string '
      'when present, got ${nextCursor.runtimeType}',
    );
  }

  return LoyaltyHistoryPage(
      entries: entries, nextCursor: nextCursor as String?);
}

LoyaltyReward _parseLoyaltyReward(Map<String, dynamic> data) {
  final rewardId = data['rewardId'];
  if (rewardId is! String) {
    throw FormatException(
      'getCustomerLoyaltyRewardCatalog response: rewardId must be a string, '
      'got ${rewardId.runtimeType}',
    );
  }
  final title = data['title'];
  if (title is! String) {
    throw FormatException(
      'getCustomerLoyaltyRewardCatalog response: title must be a string, '
      'got ${title.runtimeType}',
    );
  }
  final description = data['description'];
  if (description is! String) {
    throw FormatException(
      'getCustomerLoyaltyRewardCatalog response: description must be a '
      'string, got ${description.runtimeType}',
    );
  }
  final rewardType = data['rewardType'];
  if (rewardType is! String) {
    throw FormatException(
      'getCustomerLoyaltyRewardCatalog response: rewardType must be a '
      'string, got ${rewardType.runtimeType}',
    );
  }
  final eligibleProductIdsRaw = data['eligibleProductIds'];
  if (eligibleProductIdsRaw is! List) {
    throw FormatException(
      'getCustomerLoyaltyRewardCatalog response: eligibleProductIds must be '
      'a list, got ${eligibleProductIdsRaw.runtimeType}',
    );
  }
  final eligibleProductIds =
      eligibleProductIdsRaw.map((e) => e as String).toList(growable: false);
  final boncukCost = data['boncukCost'];
  if (boncukCost is! num) {
    throw FormatException(
      'getCustomerLoyaltyRewardCatalog response: boncukCost must be a '
      'number, got ${boncukCost.runtimeType}',
    );
  }
  final sortOrder = data['sortOrder'];
  if (sortOrder is! num) {
    throw FormatException(
      'getCustomerLoyaltyRewardCatalog response: sortOrder must be a '
      'number, got ${sortOrder.runtimeType}',
    );
  }
  final version = data['version'];
  if (version is! num) {
    throw FormatException(
      'getCustomerLoyaltyRewardCatalog response: version must be a number, '
      'got ${version.runtimeType}',
    );
  }

  return LoyaltyReward(
    rewardId: rewardId,
    title: title,
    description: description,
    rewardType: rewardType,
    eligibleProductIds: eligibleProductIds,
    boncukCost: boncukCost.toInt(),
    sortOrder: sortOrder.toInt(),
    version: version.toInt(),
  );
}

/// Parses `getCustomerLoyaltyRewardCatalog`'s decoded response.
List<LoyaltyReward> parseLoyaltyRewardCatalog(Map<String, dynamic> data) {
  final rewards = data['rewards'];
  if (rewards is! List) {
    throw FormatException(
      'getCustomerLoyaltyRewardCatalog response: rewards must be a list, '
      'got ${rewards.runtimeType}',
    );
  }
  return rewards
      .map((row) => _parseLoyaltyReward(Map<String, dynamic>.from(row as Map)))
      .toList(growable: false);
}

class FirebaseLoyaltyGateway implements LoyaltyGateway {
  FirebaseLoyaltyGateway({
    functions.FirebaseFunctions? functionsInstance,
    LoggingService? loggingService,
  })  : _functions = functionsInstance ?? functions.FirebaseFunctions.instance,
        _loggingService = loggingService ?? defaultLoggingService();

  final functions.FirebaseFunctions _functions;
  final LoggingService _loggingService;

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async {
    final callable = _functions.httpsCallable('getCustomerLoyaltySnapshot');

    Map<String, dynamic> data;
    try {
      final result = await callable.call<Map<String, dynamic>>();
      data = result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _loggingService.log(
        LogLevel.warning,
        'getCustomerLoyaltySnapshot callable threw',
        context: {'code': error.code},
      );
      throw LoyaltyGatewayException(
        error.code,
        error.message ?? 'Boncuk bakiyene şu anda ulaşılamıyor.',
      );
    }

    try {
      return parseLoyaltySnapshot(data);
    } catch (error) {
      _loggingService.log(
        LogLevel.warning,
        'getCustomerLoyaltySnapshot response parse failed',
        context: {'exceptionType': error.runtimeType.toString()},
      );
      throw const LoyaltyGatewayException(
        'parse-error',
        'Boncuk bakiyene şu anda ulaşılamıyor.',
      );
    }
  }

  @override
  Future<LoyaltyHistoryPage> getHistory({int? pageSize, String? cursor}) async {
    final callable = _functions.httpsCallable('getCustomerLoyaltyHistory');

    Map<String, dynamic> data;
    try {
      final result = await callable.call<Map<String, dynamic>>({
        if (pageSize != null) 'pageSize': pageSize,
        if (cursor != null) 'cursor': cursor,
      });
      data = result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _loggingService.log(
        LogLevel.warning,
        'getCustomerLoyaltyHistory callable threw',
        context: {'code': error.code},
      );
      throw LoyaltyGatewayException(
        error.code,
        error.message ?? 'Boncuk geçmişine şu anda ulaşılamıyor.',
      );
    }

    try {
      return parseLoyaltyHistoryPage(data);
    } catch (error) {
      _loggingService.log(
        LogLevel.warning,
        'getCustomerLoyaltyHistory response parse failed',
        context: {'exceptionType': error.runtimeType.toString()},
      );
      throw const LoyaltyGatewayException(
        'parse-error',
        'Boncuk geçmişine şu anda ulaşılamıyor.',
      );
    }
  }

  @override
  Future<List<LoyaltyReward>> getRewardCatalog() async {
    final callable =
        _functions.httpsCallable('getCustomerLoyaltyRewardCatalog');

    Map<String, dynamic> data;
    try {
      final result = await callable.call<Map<String, dynamic>>();
      data = result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _loggingService.log(
        LogLevel.warning,
        'getCustomerLoyaltyRewardCatalog callable threw',
        context: {'code': error.code},
      );
      throw LoyaltyGatewayException(
        error.code,
        error.message ?? 'Ödül kataloğuna şu anda ulaşılamıyor.',
      );
    }

    try {
      return parseLoyaltyRewardCatalog(data);
    } catch (error) {
      _loggingService.log(
        LogLevel.warning,
        'getCustomerLoyaltyRewardCatalog response parse failed',
        context: {'exceptionType': error.runtimeType.toString()},
      );
      throw const LoyaltyGatewayException(
        'parse-error',
        'Ödül kataloğuna şu anda ulaşılamıyor.',
      );
    }
  }
}
