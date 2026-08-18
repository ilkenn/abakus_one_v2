import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_business_mode_card.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester) {
    // ProfileBusinessModeCard itself needs no Riverpod state, but its
    // destination (AdminShellScreen) does, so a ProviderScope must already
    // be in the tree before the tap navigates there.
    return tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ProfileBusinessModeCard())),
      ),
    );
  }

  testWidgets('"İşletme Moduna Geç" karti dogru metinlerle gorunur', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(find.byKey(const Key('profileBusinessModeCard')), findsOneWidget);
    expect(find.text('İşletme Moduna Geç'), findsOneWidget);
    expect(find.text('Personel ve yönetim araçlarına geç'), findsOneWidget);
  });

  testWidgets('dokununca dogrudan AdminShellScreen acar', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.byKey(const Key('profileBusinessModeCard')));
    await tester.pumpAndSettle();

    expect(find.byType(AdminShellScreen), findsOneWidget);
  });

  testWidgets('375px + 1.6x text scale altinda tasma/exception olusmaz', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const Scaffold(body: ProfileBusinessModeCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
