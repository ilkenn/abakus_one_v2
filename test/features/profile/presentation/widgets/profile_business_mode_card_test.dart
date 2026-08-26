import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_business_mode_card.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester) {
    // AP-2 Stage B — the card now navigates via the real `AppRoutes.admin`
    // go_router route (`context.push`), not a raw `Navigator.push`, so the
    // test harness needs a real `GoRouter`/`MaterialApp.router` in the
    // tree, mirroring `app_router_test.dart`'s own pattern.
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: ProfileBusinessModeCard()),
        ),
        GoRoute(
          path: AppRoutes.admin,
          builder: (context, state) => const AdminShellScreen(),
        ),
      ],
    );
    return tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
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

  testWidgets('dokununca /admin rotasina gider ve AdminShellScreen acilir', (
    tester,
  ) async {
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

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: ProfileBusinessModeCard()),
        ),
        GoRoute(
          path: AppRoutes.admin,
          builder: (context, state) => const AdminShellScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
