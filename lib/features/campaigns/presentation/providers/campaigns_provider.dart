import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/logging/logging_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/campaign_gateway.dart';
import '../../domain/models/campaign.dart';

/// Server-Authoritative Campaign Engine P8-B (2026-08-25) —
/// dependency-injection seam for the real Campaign feature. Mirrors
/// `loyaltyGatewayProvider`'s established gateway-provider convention.
final campaignGatewayProvider = Provider<CampaignGateway>((ref) {
  return FirebaseCampaignGateway(
      loggingService: ref.watch(loggingServiceProvider));
});

/// The real, server-authoritative active-campaign list
/// (`getCustomerActiveCampaigns`) — replaces the old `campaignsProvider`'s
/// 4 hardcoded fake campaigns entirely. Returns an empty list, never mock
/// data, whenever no real campaign has been created by a future Admin, or
/// whenever no Firebase Auth session exists yet at all (the callable itself
/// requires SOME session — real or anonymous — so this provider avoids an
/// unauthenticated call rather than surfacing it as an error state).
///
/// Deliberately NOT gated on [isRealCustomer] — unlike
/// [loyaltyRewardCatalogProvider], an anonymous table guest is also allowed
/// to see active campaigns (locked P8-A/P8-B decision). `autoDispose` and
/// re-fetch-on-`authProvider`-change mirror every other real-data provider
/// in this codebase.
final activeCampaignsProvider =
    FutureProvider.autoDispose<List<Campaign>>((ref) async {
  final authState = ref.watch(authProvider);
  if (!authState.isAuthenticated) {
    return const [];
  }
  return ref.read(campaignGatewayProvider).getActiveCampaigns();
});
