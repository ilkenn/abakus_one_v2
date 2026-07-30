import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/courier/presentation/screens/courier_dispatch_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 1, 1, 12))),
        ],
        child: const MaterialApp(
          home: CourierDispatchDashboardScreen(branchId: 'branch-1'),
        ),
      ),
    );
  }

  testWidgets('loads and shows a healthy indicator for an empty branch',
      (tester) async {
    await pumpScreen(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sevkiyat Kontrol Merkezi'), findsOneWidget);
    expect(find.textContaining('Operasyon Durumu: Sağlıklı'), findsOneWidget);
    expect(find.text('Aktif uyarı yok.'), findsOneWidget);
    expect(find.text('Sırada bekleyen kurye yok.'), findsOneWidget);
    expect(find.text('Birden fazla aktif teslimatı olan kurye yok.'),
        findsOneWidget);

    await tester.scrollUntilVisible(find.text('Henüz kayıtlı işlem yok.'), 300);
    expect(find.text('Henüz kayıtlı işlem yok.'), findsOneWidget);
  });

  testWidgets('shows quick-action buttons to the other manager screens',
      (tester) async {
    await pumpScreen(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Canlı Harita'), findsOneWidget);
    expect(find.text('İletişim Merkezi'), findsOneWidget);
    expect(find.text('Sevkiyat Panosu'), findsOneWidget);
  });

  testWidgets('the refresh button reloads without crashing', (tester) async {
    await pumpScreen(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sevkiyat Kontrol Merkezi'), findsOneWidget);
  });
}
