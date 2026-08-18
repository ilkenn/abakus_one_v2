import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_quick_actions.dart';

void main() {
  Future<void> pumpQuickActions(
    WidgetTester tester, {
    VoidCallback? onBoncuklarim,
    VoidCallback? onSiparislerim,
    VoidCallback? onFavorilerim,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileQuickActions(
            onBoncuklarim: onBoncuklarim ?? () {},
            onSiparislerim: onSiparislerim ?? () {},
            onFavorilerim: onFavorilerim ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('tam olarak 3 hizli erisim karti gosterir, sayi/rozet yoktur', (
    tester,
  ) async {
    await pumpQuickActions(tester);

    expect(find.byKey(const Key('quickAction_boncuklarim')), findsOneWidget);
    expect(find.byKey(const Key('quickAction_siparislerim')), findsOneWidget);
    expect(find.byKey(const Key('quickAction_favorilerim')), findsOneWidget);
    expect(find.text('Boncuklarım'), findsOneWidget);
    expect(find.text('Siparişlerim'), findsOneWidget);
    expect(find.text('Favorilerim'), findsOneWidget);
    // Bakiye/adet gibi hicbir sayisal rozet yok — sadece ikon + etiket.
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
  });

  testWidgets('her karta dokununca kendi callback tetiklenir', (
    tester,
  ) async {
    var boncukTapped = false;
    var siparisTapped = false;
    var favoriTapped = false;
    await pumpQuickActions(
      tester,
      onBoncuklarim: () => boncukTapped = true,
      onSiparislerim: () => siparisTapped = true,
      onFavorilerim: () => favoriTapped = true,
    );

    await tester.tap(find.byKey(const Key('quickAction_boncuklarim')));
    await tester.tap(find.byKey(const Key('quickAction_siparislerim')));
    await tester.tap(find.byKey(const Key('quickAction_favorilerim')));
    await tester.pumpAndSettle();

    expect(boncukTapped, isTrue);
    expect(siparisTapped, isTrue);
    expect(favoriTapped, isTrue);
  });

  testWidgets('375px genislikte tasma/exception olusmaz', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpQuickActions(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('1.6x text scale altinda tasma/exception olusmaz', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: ProfileQuickActions(
            onBoncuklarim: () {},
            onSiparislerim: () {},
            onFavorilerim: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
