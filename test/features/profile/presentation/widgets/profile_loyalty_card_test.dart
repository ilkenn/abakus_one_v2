import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/screens/loyalty_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_loyalty_card.dart';

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
  Future<void> pumpCard(
    WidgetTester tester, {
    required AuthNotifier Function() authNotifierBuilder,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(authNotifierBuilder),
          // The canonical LoyaltyScreen (P3A) is real/server-authoritative
          // now — a fake gateway keeps this navigation-focused test from
          // ever touching the real (uninitialized-in-test) Firebase SDK.
          loyaltyGatewayProvider.overrideWithValue(const _FakeLoyaltyGateway()),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfileLoyaltyCard())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('premium boncuk karti gorunur, hicbir sahte bakiye gostermez', (
    tester,
  ) async {
    await pumpCard(
      tester,
      authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
    );

    expect(find.byKey(const Key('profileLoyaltyCard')), findsOneWidget);
    expect(find.text('Boncuklarını Biriktirmeye Başla'), findsOneWidget);
    expect(
      find.text('Her uygun siparişinle Boncuk kazan, ödüllere yaklaş.'),
      findsOneWidget,
    );
    expect(find.text('Boncukları Keşfet'), findsOneWidget);
    expect(find.textContaining('320'), findsNothing);
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
  });

  testWidgets('kimlik dogrulanmis kullanicida dokununca LoyaltyScreen acar', (
    tester,
  ) async {
    await pumpCard(
      tester,
      authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905551112233'),
    );

    await tester.tap(find.byKey(const Key('profileLoyaltyCard')));
    await tester.pumpAndSettle();

    expect(find.byType(LoyaltyScreen), findsOneWidget);
  });

  testWidgets('misafirde dokununca LoginScreen acar, LoyaltyScreen degil', (
    tester,
  ) async {
    await pumpCard(tester, authNotifierBuilder: () => _SignedOutNotifier());

    await tester.tap(find.byKey(const Key('profileLoyaltyCard')));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(LoyaltyScreen), findsNothing);
  });

  testWidgets(
      'misafirde de ayni premium metin gorunur, boncuk gecmisi/ilerlemesi '
      'yoktur', (tester) async {
    await pumpCard(tester, authNotifierBuilder: () => _SignedOutNotifier());

    expect(find.text('Boncuklarını Biriktirmeye Başla'), findsOneWidget);
    expect(find.text('Boncukları Keşfet'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
  });
}

class _FakeLoyaltyGateway implements LoyaltyGateway {
  const _FakeLoyaltyGateway();

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async =>
      LoyaltyAccountSnapshot.zero;

  @override
  Future<LoyaltyHistoryPage> getHistory(
          {int? pageSize, String? cursor}) async =>
      LoyaltyHistoryPage.empty;
}
