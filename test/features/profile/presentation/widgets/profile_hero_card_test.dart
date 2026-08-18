import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/profile/domain/models/profile_model.dart';
import 'package:abakus_one_v2/features/profile/presentation/providers/profile_provider.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_hero_card.dart';

class _SignedInNotifier extends AuthNotifier {
  _SignedInNotifier(this.uid, this.phoneNumber);
  final String uid;
  final String phoneNumber;

  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: uid,
          phoneNumber: phoneNumber,
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        ),
      );
}

class _SignedOutNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: false, isGuest: false);
}

void main() {
  Future<void> pumpHero(
    WidgetTester tester, {
    required AuthNotifier Function() authNotifierBuilder,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(authNotifierBuilder)],
        child: const MaterialApp(home: Scaffold(body: ProfileHeroCard())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('kimlik dogrulanmis (authenticated)', () {
    testWidgets('gercek telefon numarasini birincil kimlik olarak gosterir', (
      tester,
    ) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
      );

      expect(find.text('+905551112233'), findsOneWidget);
      expect(find.text('Ahmet Yılmaz'), findsNothing);
    });

    testWidgets('email bos oldugunda email satiri render edilmez', (
      tester,
    ) async {
      // Gercek oturumlar bugun asla email toplamiyor (telefon+OTP) —
      // ProfileNotifier bu durumda her zaman email:'' doner.
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
      );

      expect(find.text('ahmet.yilmaz@abakusbowl.com'), findsNothing);
      // Sadece isim/telefon satiri var — Column'da ikinci bir Text yok.
      expect(
        find.descendant(
          of: find.byType(ProfileHeroCard),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
    });

    testWidgets('email doluysa email satiri render edilir', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(
              () => _FixedProfileNotifier(
                const ProfileModel(
                  id: 'uid-1',
                  name: '+905551112233',
                  email: 'gercek@musteri.com',
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ProfileHeroCard())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('gercek@musteri.com'), findsOneWidget);
    });
  });

  group('misafir (guest)', () {
    testWidgets('sahte kimlik gostermez, giris yap CTAsi sunar', (
      tester,
    ) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedOutNotifier(),
      );

      expect(find.text('Ahmet Yılmaz'), findsNothing);
      expect(find.text('ahmet.yilmaz@abakusbowl.com'), findsNothing);
      expect(find.textContaining('user_123'), findsNothing);
      expect(find.text('Hesabına Giriş Yap'), findsOneWidget);
    });

    testWidgets('dokununca gercek LoginScreen acilir', (tester) async {
      await pumpHero(
        tester,
        authNotifierBuilder: () => _SignedOutNotifier(),
      );

      await tester.tap(find.text('Hesabına Giriş Yap'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}

class _FixedProfileNotifier extends ProfileNotifier {
  _FixedProfileNotifier(this._value);
  final ProfileModel _value;

  @override
  ProfileModel? build() => _value;
}
