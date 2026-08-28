import 'package:abakus_one_v2/features/platform/domain/authorization/platform_actor_session.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:abakus_one_v2/features/platform/presentation/providers/platform_actor_session_provider.dart';
import 'package:abakus_one_v2/features/platform/presentation/screens/platform_shell_screen.dart';
import 'package:abakus_one_v2/features/platform/presentation/screens/platform_sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester,
      {PlatformActorSession? session}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (session != null)
            platformActorSessionProvider.overrideWith((ref) => session),
        ],
        child: const MaterialApp(home: PlatformShellScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('falls back to PlatformSignInScreen with no active session',
      (tester) async {
    await pumpShell(tester);

    expect(find.byType(PlatformSignInScreen), findsOneWidget);
  });

  testWidgets(
      'a platformOwner session sees the 5-tab shell (AP-3 continuation '
      'added Müşteriler) with Monitoring as the default tab', (tester) async {
    await pumpShell(
      tester,
      session: const PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      ),
    );

    expect(find.text('Platform Merkezi'), findsOneWidget);
    expect(find.text('İzleme'), findsOneWidget);
    expect(find.text('Yayın Hazırlığı'), findsOneWidget);
    expect(find.text('Mağaza Uyumluluğu'), findsOneWidget);
    expect(find.text('Abonelikler'), findsOneWidget);
    expect(find.text('Müşteriler'), findsOneWidget);
    expect(find.text('Kiracı Organizasyon'), findsOneWidget);
  });

  testWidgets(
      'switching to the Müşteriler tab shows the real customer directory '
      '(backend-unavailable error state under flutter test, never a crash)',
      (tester) async {
    await pumpShell(
      tester,
      session: const PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      ),
    );

    await tester.tap(find.text('Müşteriler'));
    await tester.pumpAndSettle();

    expect(
      find.text('Müşteri dizini şu anda kullanılamıyor.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'switching to the Abonelikler tab shows the real entitlement console '
      '(backend-unavailable error state under flutter test, never a crash)',
      (tester) async {
    await pumpShell(
      tester,
      session: const PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      ),
    );

    await tester.tap(find.text('Abonelikler'));
    await tester.pumpAndSettle();

    expect(find.text('Abonelik Yönetimi'), findsOneWidget);
    expect(find.text('İşletme dizinine ulaşılamadı.'), findsOneWidget);
  });

  testWidgets('switching to the Release Readiness tab shows real criteria',
      (tester) async {
    await pumpShell(
      tester,
      session: const PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      ),
    );

    await tester.tap(find.text('Yayın Hazırlığı'));
    await tester.pumpAndSettle();

    expect(find.text('Çökme Raporlama'), findsOneWidget);
  });

  testWidgets('switching to the Store Compliance tab shows real criteria',
      (tester) async {
    await pumpShell(
      tester,
      session: const PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      ),
    );

    await tester.tap(find.text('Mağaza Uyumluluğu'));
    await tester.pumpAndSettle();

    expect(find.text('Hesap Silme'), findsOneWidget);
  });

  testWidgets('signing out returns to PlatformSignInScreen', (tester) async {
    await pumpShell(
      tester,
      session: const PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      ),
    );

    await tester.tap(find.byIcon(Icons.logout_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(PlatformSignInScreen), findsOneWidget);
  });
}
