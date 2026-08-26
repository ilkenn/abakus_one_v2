import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../../../core/services/logging/log_level.dart';
import '../../../core/services/logging/logging_provider.dart';
import '../../../core/services/logging/logging_service.dart';
import '../domain/models/campaign.dart';

class CampaignGatewayException implements Exception {
  const CampaignGatewayException(this.code, this.message);

  /// A `FirebaseFunctionsException.code` value, or `'parse-error'`/
  /// `'unknown'` for a non-`FirebaseFunctionsException` failure. Callers
  /// branch on this, never on [message]'s text.
  final String code;
  final String message;

  @override
  String toString() => 'CampaignGatewayException($code): $message';
}

/// Server-Authoritative Campaign Engine P8-B (2026-08-25) — the
/// customer-side bridge to `functions/src/getCustomerActiveCampaigns.ts`.
/// Mirrors `LoyaltyGateway`'s exact discipline: never sends
/// `organizationId`/`customerId`/`uid` — identity is resolved exclusively
/// server-side.
abstract interface class CampaignGateway {
  /// Returns only currently active/non-archived/currently-scheduled
  /// campaigns for the caller's own tenant, already sorted by `sortOrder`
  /// — the server's own contract, never re-filtered/re-sorted client-side.
  /// Reachable by BOTH a real, phone-verified customer AND an anonymous
  /// table guest (unlike [LoyaltyGateway.getRewardCatalog]) — the server
  /// callable itself allows both identity types.
  Future<List<Campaign>> getActiveCampaigns();
}

DateTime? _parseOptionalIso(dynamic raw, String field, String context) {
  if (raw == null) return null;
  if (raw is! String) {
    throw FormatException(
        '$context: $field must be a string when present, got ${raw.runtimeType}');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException(
        '$context: $field must be a valid ISO 8601 timestamp string, got $raw');
  }
  return parsed;
}

CampaignRecurringWindow _parseRecurringWindow(Map<String, dynamic> data) {
  final weekdaysRaw = data['weekdays'];
  if (weekdaysRaw is! List) {
    throw const FormatException(
      'getCustomerActiveCampaigns response: recurringWindows[].weekdays must be a list',
    );
  }
  final startMinute = data['startMinute'];
  final endMinute = data['endMinute'];
  if (startMinute is! num || endMinute is! num) {
    throw const FormatException(
      'getCustomerActiveCampaigns response: recurringWindows[].startMinute/endMinute must be numbers',
    );
  }
  return CampaignRecurringWindow(
    weekdays:
        weekdaysRaw.map((e) => (e as num).toInt()).toList(growable: false),
    startMinute: startMinute.toInt(),
    endMinute: endMinute.toInt(),
  );
}

CampaignSchedule _parseSchedule(Map<String, dynamic> data) {
  final mode = data['mode'];
  if (mode is! String) {
    throw const FormatException(
        'getCustomerActiveCampaigns response: schedule.mode must be a string');
  }
  const context = 'getCustomerActiveCampaigns response.schedule';
  if (mode == 'oneTime') {
    return CampaignSchedule(
      mode: mode,
      startAt: _parseOptionalIso(data['startAt'], 'startAt', context),
      endAt: _parseOptionalIso(data['endAt'], 'endAt', context),
    );
  }
  final windowsRaw = data['recurringWindows'];
  if (windowsRaw is! List) {
    throw const FormatException(
        'getCustomerActiveCampaigns response: schedule.recurringWindows must be a list');
  }
  return CampaignSchedule(
    mode: mode,
    recurringWindows: windowsRaw
        .map((w) => _parseRecurringWindow(Map<String, dynamic>.from(w as Map)))
        .toList(growable: false),
  );
}

CampaignRule _parseRule(Map<String, dynamic> data) {
  try {
    return CampaignRule.fromMap(data);
  } on FormatException catch (error) {
    throw FormatException(
        'getCustomerActiveCampaigns response: ${error.message}');
  }
}

Campaign _parseCampaign(Map<String, dynamic> data) {
  const context = 'getCustomerActiveCampaigns response';
  final campaignId = data['campaignId'];
  if (campaignId is! String) {
    throw FormatException(
        '$context: campaignId must be a string, got ${campaignId.runtimeType}');
  }
  final title = data['title'];
  if (title is! String) {
    throw FormatException(
        '$context: title must be a string, got ${title.runtimeType}');
  }
  final description = data['description'];
  if (description is! String) {
    throw FormatException(
        '$context: description must be a string, got ${description.runtimeType}');
  }
  final campaignType = data['campaignType'];
  if (campaignType is! String) {
    throw FormatException(
        '$context: campaignType must be a string, got ${campaignType.runtimeType}');
  }
  final ruleRaw = data['rule'];
  if (ruleRaw is! Map) {
    throw FormatException(
        '$context: rule must be an object, got ${ruleRaw.runtimeType}');
  }
  final eligibleChannelsRaw = data['eligibleChannels'];
  if (eligibleChannelsRaw is! List) {
    throw FormatException(
        '$context: eligibleChannels must be a list, got ${eligibleChannelsRaw.runtimeType}');
  }
  final scheduleRaw = data['schedule'];
  if (scheduleRaw is! Map) {
    throw FormatException(
        '$context: schedule must be an object, got ${scheduleRaw.runtimeType}');
  }
  final sortOrder = data['sortOrder'];
  if (sortOrder is! num) {
    throw FormatException(
        '$context: sortOrder must be a number, got ${sortOrder.runtimeType}');
  }
  final version = data['version'];
  if (version is! num) {
    throw FormatException(
        '$context: version must be a number, got ${version.runtimeType}');
  }

  final eligibleProductIdsRaw = data['eligibleProductIds'];
  final eligibleCategoryIdsRaw = data['eligibleCategoryIds'];
  final minimumBasketMinorUnits = data['minimumBasketMinorUnits'];

  return Campaign(
    campaignId: campaignId,
    title: title,
    description: description,
    campaignType: campaignType,
    rule: _parseRule(Map<String, dynamic>.from(ruleRaw)),
    eligibleChannels:
        eligibleChannelsRaw.map((e) => e as String).toList(growable: false),
    eligibleProductIds: eligibleProductIdsRaw == null
        ? null
        : (eligibleProductIdsRaw as List)
            .map((e) => e as String)
            .toList(growable: false),
    eligibleCategoryIds: eligibleCategoryIdsRaw == null
        ? null
        : (eligibleCategoryIdsRaw as List)
            .map((e) => e as String)
            .toList(growable: false),
    minimumBasketMinorUnits: minimumBasketMinorUnits == null
        ? null
        : (minimumBasketMinorUnits as num).toInt(),
    schedule: _parseSchedule(Map<String, dynamic>.from(scheduleRaw)),
    sortOrder: sortOrder.toInt(),
    version: version.toInt(),
  );
}

/// Parses `getCustomerActiveCampaigns`'s decoded response.
List<Campaign> parseActiveCampaigns(Map<String, dynamic> data) {
  final campaigns = data['campaigns'];
  if (campaigns is! List) {
    throw FormatException(
      'getCustomerActiveCampaigns response: campaigns must be a list, got ${campaigns.runtimeType}',
    );
  }
  return campaigns
      .map((row) => _parseCampaign(Map<String, dynamic>.from(row as Map)))
      .toList(growable: false);
}

class FirebaseCampaignGateway implements CampaignGateway {
  FirebaseCampaignGateway({
    functions.FirebaseFunctions? functionsInstance,
    LoggingService? loggingService,
  })  : _functions = functionsInstance ?? functions.FirebaseFunctions.instance,
        _loggingService = loggingService ?? defaultLoggingService();

  final functions.FirebaseFunctions _functions;
  final LoggingService _loggingService;

  @override
  Future<List<Campaign>> getActiveCampaigns() async {
    final callable = _functions.httpsCallable('getCustomerActiveCampaigns');

    Map<String, dynamic> data;
    try {
      final result = await callable.call<Map<String, dynamic>>();
      data = result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _loggingService.log(
        LogLevel.warning,
        'getCustomerActiveCampaigns callable threw',
        context: {'code': error.code},
      );
      throw CampaignGatewayException(
        error.code,
        error.message ?? 'Kampanyalara şu anda ulaşılamıyor.',
      );
    }

    try {
      return parseActiveCampaigns(data);
    } catch (error) {
      _loggingService.log(
        LogLevel.warning,
        'getCustomerActiveCampaigns response parse failed',
        context: {'exceptionType': error.runtimeType.toString()},
      );
      throw const CampaignGatewayException(
        'parse-error',
        'Kampanyalara şu anda ulaşılamıyor.',
      );
    }
  }
}
