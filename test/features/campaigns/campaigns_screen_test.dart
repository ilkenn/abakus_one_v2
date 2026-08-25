import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/campaigns/data/campaign_gateway.dart';
import 'package:abakus_one_v2/features/campaigns/domain/models/campaign.dart';
import 'package:abakus_one_v2/features/campaigns/presentation/providers/campaigns_provider.dart';
import 'package:abakus_one_v2/features/campaigns/presentation/screens/campaign_detail_screen.dart';
import 'package:abakus_one_v2/features/campaigns/presentation/screens/campaigns_screen.dart';

/// Server-Authoritative Campaign Engine P8-B (2026-08-25) — rewritten
/// entirely for the new real, server-authoritative Campaign feature.
/// Replaces the previous mock-`campaignsProvider`-backed tests (which
/// asserted on the 4 hardcoded fake campaigns and their coupon codes) with
/// a fake [CampaignGateway], mirroring `rewards_screen_test.dart`'s own
/// established pattern for a real, callable-backed provider.
class _FakeCampaignGateway implements CampaignGateway {
  _FakeCampaignGateway({this.campaigns = const [], this.errorToThrow});

  final List<Campaign> campaigns;
  final Object? errorToThrow;
  int callCount = 0;

  @override
  Future<List<Campaign>> getActiveCampaigns() async {
    callCount += 1;
    if (errorToThrow != null) throw errorToThrow!;
    return campaigns;
  }
}

class _AuthenticatedNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: 'test-customer-uid',
          phoneNumber: '+905551112233',
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        ),
      );
}

Campaign _campaign({
  String campaignId = 'test-campaign',
  String title = 'Test Kampanya',
  String description = 'Bir test kampanyası.',
  String campaignType = 'percentageDiscount',
  List<String> eligibleChannels = const ['dineIn', 'takeaway'],
}) {
  return Campaign(
    campaignId: campaignId,
    title: title,
    description: description,
    campaignType: campaignType,
    rule: const CampaignRule(
        mechanic: 'percentage', percentBasisPoints: 1500, scopeKind: 'order'),
    eligibleChannels: eligibleChannels,
    eligibleProductIds: null,
    eligibleCategoryIds: null,
    minimumBasketMinorUnits: null,
    schedule: const CampaignSchedule(mode: 'oneTime'),
    sortOrder: 0,
    version: 1,
  );
}

void main() {
  Future<void> pumpCampaignsScreen(
    WidgetTester tester, {
    required CampaignGateway gateway,
    bool authenticated = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignGatewayProvider.overrideWithValue(gateway),
          if (authenticated)
            authProvider.overrideWith(() => _AuthenticatedNotifier()),
        ],
        child: const MaterialApp(home: CampaignsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'shows a loading state, then the empty state when no real campaign exists',
      (
    WidgetTester tester,
  ) async {
    await pumpCampaignsScreen(tester, gateway: _FakeCampaignGateway());

    expect(find.text('Şu anda aktif kampanya bulunmuyor.'), findsOneWidget);
  });

  testWidgets(
      'renders real campaigns from the CampaignGateway, never mock/local data',
      (
    WidgetTester tester,
  ) async {
    final gateway = _FakeCampaignGateway(
      campaigns: [
        _campaign(campaignId: 'a', title: 'Hafta İçi Öğle'),
        _campaign(campaignId: 'b', title: '%15 Paket Servis')
      ],
    );
    await pumpCampaignsScreen(tester, gateway: gateway);

    expect(find.text('Hafta İçi Öğle'), findsOneWidget);
    expect(find.text('%15 Paket Servis'), findsOneWidget);
    expect(gateway.callCount, 1);
  });

  testWidgets('shows an error state with retry when the gateway throws', (
    WidgetTester tester,
  ) async {
    await pumpCampaignsScreen(
      tester,
      gateway: _FakeCampaignGateway(
          errorToThrow: const CampaignGatewayException('unavailable', 'nope')),
    );

    expect(find.text('Kampanyalar şu anda yüklenemedi.'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });

  testWidgets(
      'tapping a campaign card opens CampaignDetailScreen with the real campaign data',
      (
    WidgetTester tester,
  ) async {
    final gateway =
        _FakeCampaignGateway(campaigns: [_campaign(title: 'Hafta İçi Öğle')]);
    await pumpCampaignsScreen(tester, gateway: gateway);

    await tester.tap(find.text('Hafta İçi Öğle'));
    await tester.pumpAndSettle();

    expect(find.byType(CampaignDetailScreen), findsOneWidget);
    expect(find.text('Kampanya Detayı'), findsOneWidget);
    expect(find.text('Hafta İçi Öğle'), findsWidgets);
  });

  testWidgets(
      'an anonymous (guest) session also sees real campaigns — locked decision, unlike the Reward Catalog',
      (
    WidgetTester tester,
  ) async {
    final gateway = _FakeCampaignGateway(
        campaigns: [_campaign(title: 'Herkese Açık Kampanya')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignGatewayProvider.overrideWithValue(gateway),
          authProvider.overrideWith(() => _GuestAuthenticatedNotifier()),
        ],
        child: const MaterialApp(home: CampaignsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Herkese Açık Kampanya'), findsOneWidget);
  });

  testWidgets(
      'an unauthenticated session (no session at all) never touches the gateway, shows the empty state',
      (
    WidgetTester tester,
  ) async {
    final gateway = _FakeCampaignGateway(
        campaigns: [_campaign(title: 'Should Not Appear')]);
    await pumpCampaignsScreen(tester, gateway: gateway, authenticated: false);

    expect(find.text('Should Not Appear'), findsNothing);
    expect(gateway.callCount, 0);
  });
}

class _GuestAuthenticatedNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: true,
        session: AuthSession(
          uid: 'test-guest-uid',
          phoneNumber: '',
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        ),
      );
}
