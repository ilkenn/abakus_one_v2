import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_station.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/kds_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/kds_station_lock_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/kds_test_fixtures.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required InMemoryKdsStationLockStore store,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kdsStationLockStoreProvider.overrideWith((ref) async => store),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const KdsStationLockSettingsScreen(),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'no existing lock shows the unlocked status and every station option',
      (tester) async {
    await pumpScreen(tester, store: InMemoryKdsStationLockStore());

    expect(find.text('Şu anda kilit yok — Tümü gösteriliyor'), findsOneWidget);
    expect(find.text('Sıcak'), findsOneWidget);
    expect(find.text('Soğuk'), findsOneWidget);
    expect(find.text('İçecek'), findsOneWidget);
    expect(find.text('Tatlı'), findsOneWidget);
    expect(find.text('Paketleme'), findsOneWidget);
    expect(find.text('Ortak'), findsOneWidget);
    expect(find.text('Kilidi Kaldır / Tümünü Göster'), findsOneWidget);
  });

  testWidgets('selecting a station and saving persists the lock and pops back',
      (tester) async {
    final store = InMemoryKdsStationLockStore();
    await pumpScreen(tester, store: store);

    await tester.tap(find.text('Sıcak'));
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(await store.currentLock(), KitchenStation.hot);
    expect(find.byType(KdsStationLockSettingsScreen), findsNothing);
  });

  testWidgets(
      'an existing lock shows the locked status and selecting Kilidi Kaldır clears it',
      (tester) async {
    final store = InMemoryKdsStationLockStore(KitchenStation.cold);
    await pumpScreen(tester, store: store);

    expect(find.text('Şu anda kilitli: Soğuk'), findsOneWidget);

    await tester.tap(find.text('Kilidi Kaldır / Tümünü Göster'));
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(await store.currentLock(), isNull);
  });
}
