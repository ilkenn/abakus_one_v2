import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:abakus_one_v2/features/feedback/presentation/screens/customer_feedback_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/staff_sign_in_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/help_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/loyalty_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/profile_screen.dart';

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;
  _FakeSessionStorage({this.stored});
  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> writeSession(AuthSession session) async => stored = session;
  @override
  Future<void> clearSession() async => stored = null;
}

void main() {
  Future<void> pumpProfileScreen(
    WidgetTester tester, {
    _FakeSessionStorage? sessionStorage,
    ActorSession? actorSession,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            DevelopmentLocalAuthRepository(
              sessionStorage: sessionStorage ?? _FakeSessionStorage(),
            ),
          ),
          if (actorSession != null)
            actorSessionProvider.overrideWith((ref) => actorSession),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
  }

  testWidgets('Favorilerim menu ogesi FavoritesScreen acar', (
    WidgetTester tester,
  ) async {
    await pumpProfileScreen(tester);

    await tester.tap(find.text('Favorilerim'));
    await tester.pumpAndSettle();

    expect(find.byType(FavoritesScreen), findsOneWidget);
  });

  testWidgets(
    'Sadakat Boncuklarim menu ogesi LoyaltyScreen acar ve boncuk gecmisini gosterir',
    (WidgetTester tester) async {
      await pumpProfileScreen(tester);

      await tester.tap(find.text('Sadakat Boncuklarım'));
      await tester.pumpAndSettle();

      expect(find.byType(LoyaltyScreen), findsOneWidget);

      // Boncuk Geçmişi listesini gorunur hale getirip ListTile'larin
      // Material ink-splash assertion'i tetiklemeden render edildigini dogrula.
      final loyaltyScroll = find
          .descendant(
            of: find.byType(LoyaltyScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.dragUntilVisible(
        find.text('Protein Bowl Siparişi'),
        loyaltyScroll,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protein Bowl Siparişi'), findsOneWidget);
    },
  );

  testWidgets('Yardim ve Destek menu ogesi HelpScreen acar', (
    WidgetTester tester,
  ) async {
    await pumpProfileScreen(tester);

    await tester.ensureVisible(find.text('Yardım ve Destek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yardım ve Destek'));
    await tester.pumpAndSettle();

    expect(find.byType(HelpScreen), findsOneWidget);
  });

  testWidgets(
    'Cikis Yap onay diyalogundan sonra oturumu temizler ve LoginScreen\'e '
    'geri doner, geri tusuyla ProfileScreen\'e donulmez',
    (WidgetTester tester) async {
      final storage = _FakeSessionStorage(
        stored: AuthSession(
          phoneNumber: '+905321234567',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      await pumpProfileScreen(tester, sessionStorage: storage);

      await tester.ensureVisible(find.text('Çıkış Yap').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Çıkış Yap').first);
      await tester.pumpAndSettle();

      // Onay diyalogu acildi, "Cikis Yap" aksiyonuna basiliyor.
      await tester.tap(find.text('Çıkış Yap').last);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
      expect(storage.stored, isNull);
    },
  );

  testWidgets(
    'Ziyaret Pasosu menu ogesi mevcuttur (Sprint 5E)',
    (WidgetTester tester) async {
      await pumpProfileScreen(tester);

      expect(find.text('Ziyaret Pasosu'), findsOneWidget);
    },
  );

  testWidgets(
    'Geri Bildirim Gonder menu ogesi CustomerFeedbackScreen acar '
    '(Sprint 5E)',
    (WidgetTester tester) async {
      await pumpProfileScreen(tester);

      await tester.ensureVisible(find.text('Geri Bildirim Gönder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Geri Bildirim Gönder'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerFeedbackScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Yonetici Paneli menu ogesi oturum yokken StaffSignInScreen acar '
    '(Sprint 6B)',
    (WidgetTester tester) async {
      await pumpProfileScreen(tester);

      expect(find.text('Yönetici Paneli'), findsOneWidget);

      await tester.ensureVisible(find.text('Yönetici Paneli'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yönetici Paneli'));
      await tester.pumpAndSettle();

      expect(find.byType(StaffSignInScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Yonetici Paneli menu ogesi bir personel rolu ile AdminShellScreen '
    'acar (Phase 6A)',
    (WidgetTester tester) async {
      await pumpProfileScreen(
        tester,
        actorSession: const ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        ),
      );

      expect(find.text('Yönetici Paneli'), findsOneWidget);

      await tester.ensureVisible(find.text('Yönetici Paneli'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yönetici Paneli'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminShellScreen), findsOneWidget);
    },
  );
}
