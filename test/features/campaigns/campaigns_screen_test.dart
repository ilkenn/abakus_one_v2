import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/campaigns/presentation/screens/campaign_detail_screen.dart';
import 'package:abakus_one_v2/features/campaigns/presentation/screens/campaigns_screen.dart';

void main() {
  Future<void> pumpCampaignsScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CampaignsScreen()),
      ),
    );
  }

  testWidgets('CampaignsScreen gercek campaignsProvider verisini gosterir', (
    WidgetTester tester,
  ) async {
    await pumpCampaignsScreen(tester);

    expect(find.text('Tüm Kaselerde %10 İndirim!'), findsOneWidget);
    expect(find.text('İlk Siparişe 100 TL Hediye'), findsOneWidget);
  });

  testWidgets(
    'Kampanya kartina dokununca CampaignDetailScreen acilir',
    (WidgetTester tester) async {
      await pumpCampaignsScreen(tester);

      await tester.tap(find.text('Tüm Kaselerde %10 İndirim!'));
      await tester.pumpAndSettle();

      expect(find.byType(CampaignDetailScreen), findsOneWidget);
      expect(find.text('Kampanya Detayı'), findsOneWidget);
    },
  );
}
