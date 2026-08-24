import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/screens/loyalty_screen.dart';

/// P3A (2026-08-23) — widget tests for the real, server-authoritative
/// Boncuklarım screen. Mirrors `complete_profile_screen_test.dart`'s exact
/// `ProviderScope` override + `SeededAuthNotifier` pattern.
void main() {
  AuthState realCustomerState() {
    return AuthState(
      isAuthenticated: true,
      isGuest: false,
      session: AuthSession(
        uid: 'customer-uid-1',
        phoneNumber: '+905551234567',
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2027, 1, 1),
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    AuthState? authState,
    _FakeLoyaltyGateway? gateway,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => SeededAuthNotifier(authState ?? realCustomerState()),
          ),
          loyaltyGatewayProvider
              .overrideWithValue(gateway ?? _FakeLoyaltyGateway()),
        ],
        child: const MaterialApp(home: LoyaltyScreen()),
      ),
    );
  }

  testWidgets(
      'a guest session sees the sign-in prompt, never a fabricated balance',
      (tester) async {
    await pumpScreen(
      tester,
      authState: const AuthState(isAuthenticated: false, isGuest: true),
    );
    await tester.pump();

    expect(find.byKey(const Key('loyaltyGuestPrompt')), findsOneWidget);
    expect(find.byKey(const Key('abacusCardBalance')), findsNothing);
  });

  testWidgets(
      'loading shows the premium skeleton, not a blank/generic spinner-only screen',
      (tester) async {
    await pumpScreen(
      tester,
      gateway: _FakeLoyaltyGateway(neverCompleteSnapshot: true),
    );
    await tester.pump();

    expect(find.byKey(const Key('loyaltyScreenSkeleton')), findsOneWidget);
  });

  testWidgets(
      'a zero-balance real account shows 0, the canonical zero state — never a fallback 320',
      (tester) async {
    await pumpScreen(tester,
        gateway: _FakeLoyaltyGateway(snapshot: LoyaltyAccountSnapshot.zero));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsWidgets);
    expect(find.textContaining('320'), findsNothing);
  });

  testWidgets('a real non-zero balance renders exactly that number',
      (tester) async {
    await pumpScreen(
      tester,
      gateway: _FakeLoyaltyGateway(
        snapshot: const LoyaltyAccountSnapshot(
          spendableBalance: 14,
          boncukDebt: 0,
          earningRemainderMinorUnits: 100,
          minorUnitsUntilNextBoncuk: 900,
          lifetimeEarned: 14,
          lifetimeRedeemed: 0,
          earningSpendMinorUnits: 5000,
          earningBoncukAmount: 5,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('abacusCardBalance')), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.textContaining('≈ 14 TL'), findsOneWidget);
  });

  testWidgets('the hero shows the locked redemption rate, 1 Boncuk = 1 TL',
      (tester) async {
    await pumpScreen(
      tester,
      gateway: _FakeLoyaltyGateway(
        snapshot: const LoyaltyAccountSnapshot(
          spendableBalance: 5,
          boncukDebt: 0,
          earningRemainderMinorUnits: 0,
          minorUnitsUntilNextBoncuk: 1000,
          lifetimeEarned: 5,
          lifetimeRedeemed: 0,
          earningSpendMinorUnits: 5000,
          earningBoncukAmount: 5,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 Boncuk = 1 TL'), findsOneWidget);
    expect(find.textContaining('1 Boncuk = 2 TL'), findsNothing);
  });

  testWidgets(
      'the earning-remainder progress renders from the real snapshot field, e.g. 4 TL / 10 TL',
      (tester) async {
    await pumpScreen(
      tester,
      gateway: _FakeLoyaltyGateway(
        snapshot: const LoyaltyAccountSnapshot(
          spendableBalance: 0,
          boncukDebt: 0,
          earningRemainderMinorUnits: 400,
          minorUnitsUntilNextBoncuk: 600,
          lifetimeEarned: 0,
          lifetimeRedeemed: 0,
          earningSpendMinorUnits: 5000,
          earningBoncukAmount: 5,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sonraki Boncuğa'), findsOneWidget);
    expect(find.text('4 TL / 10 TL'), findsOneWidget);
    expect(find.textContaining('6 TL kaldı'), findsOneWidget);
  });

  testWidgets(
      'a nonzero debt shows the calm explanatory state, never "borçlusun"/legalistic wording',
      (tester) async {
    await pumpScreen(
      tester,
      gateway: _FakeLoyaltyGateway(
        snapshot: const LoyaltyAccountSnapshot(
          spendableBalance: 0,
          boncukDebt: 7,
          earningRemainderMinorUnits: 0,
          minorUnitsUntilNextBoncuk: 1000,
          lifetimeEarned: 0,
          lifetimeRedeemed: 0,
          earningSpendMinorUnits: 5000,
          earningBoncukAmount: 5,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('abacusCardDebtExplainer')), findsOneWidget);
    expect(
      find.textContaining(
          'İade nedeniyle 7 Boncuk sonraki kazanımlarından dengelenecek.'),
      findsOneWidget,
    );
    expect(find.textContaining('borçlusun'), findsNothing);
    expect(find.textContaining('borç'), findsNothing);
  });

  testWidgets(
      'no movements yet shows the honest empty state, never a fake transaction',
      (tester) async {
    await pumpScreen(tester, gateway: _FakeLoyaltyGateway());
    await tester.pumpAndSettle();

    expect(find.text('Henüz Boncuk hareketin yok.'), findsOneWidget);
  });

  testWidgets('a populated history renders real movement rows', (tester) async {
    await pumpScreen(
      tester,
      gateway: _FakeLoyaltyGateway(
        historyPage: LoyaltyHistoryPage(
          entries: [
            LoyaltyHistoryEntry(
              eventId: 'e1',
              type: LoyaltyLedgerEntryType.orderEarn,
              displayBoncukDelta: 10,
              debtAppliedBoncuk: 0,
              occurredAt: DateTime(2026, 8, 20),
              orderId: null,
            ),
          ],
          nextCursor: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Siparişten Boncuk kazandın'), findsOneWidget);
    expect(find.text('+10 Boncuk'), findsOneWidget);
  });

  testWidgets(
      'a snapshot backend error shows an honest retry state, and retry re-invokes the gateway',
      (tester) async {
    final gateway = _FakeLoyaltyGateway(
      snapshotError: const LoyaltyGatewayException('unavailable', 'boom'),
    );
    await pumpScreen(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text('Tekrar Dene'), findsWidgets);
    expect(gateway.snapshotCalls, 1);

    gateway.snapshotError = null;
    gateway.snapshot = LoyaltyAccountSnapshot.zero;
    await tester.tap(find.text('Tekrar Dene').first);
    await tester.pumpAndSettle();

    expect(gateway.snapshotCalls, 2);
    expect(find.byKey(const Key('abacusCardBalance')), findsOneWidget);
  });

  testWidgets('never shows bronze/silver/gold tier language', (tester) async {
    await pumpScreen(tester, gateway: _FakeLoyaltyGateway());
    await tester.pumpAndSettle();

    for (final forbidden in ['Bronz', 'Gümüş', 'Altın', 'seviye']) {
      expect(find.textContaining(forbidden), findsNothing,
          reason: '"$forbidden" must not appear');
    }
  });

  testWidgets('never shows a mock rewards catalog or a spin-wheel affordance',
      (tester) async {
    await pumpScreen(tester, gateway: _FakeLoyaltyGateway());
    await tester.pumpAndSettle();

    expect(find.textContaining('Şans Çarkı'), findsNothing);
    expect(find.textContaining('Boncuklarını Harca'), findsNothing);
    expect(find.byIcon(Icons.casino), findsNothing);
  });

  testWidgets(
      'How It Works renders the 3 compact chips with the real locked rates',
      (tester) async {
    await pumpScreen(tester, gateway: _FakeLoyaltyGateway());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loyaltyHowItWorksCard')), findsOneWidget);
    expect(find.text('50 TL → 5 Boncuk'), findsOneWidget);
    expect(find.text('1 Boncuk → 1 TL'), findsOneWidget);
    expect(find.text("En fazla %50'si"), findsOneWidget);
  });

  testWidgets(
      'How It Works reflects a different organization policy verbatim — proves the copy is server-driven, never hardcoded',
      (tester) async {
    await pumpScreen(
      tester,
      gateway: _FakeLoyaltyGateway(
        snapshot: const LoyaltyAccountSnapshot(
          spendableBalance: 0,
          boncukDebt: 0,
          earningRemainderMinorUnits: 0,
          minorUnitsUntilNextBoncuk: 3000,
          lifetimeEarned: 0,
          lifetimeRedeemed: 0,
          earningSpendMinorUnits: 9000,
          earningBoncukAmount: 3,
          redemptionValueMinorUnitsPerBoncuk: 250,
          maxRedemptionBasisPoints: 10000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('90 TL → 3 Boncuk'), findsOneWidget);
    // 250 minor units = 2.50 TL — a genuinely fractional redemption value,
    // rendered exactly, never rounded to a whole "3 TL".
    expect(find.text('1 Boncuk → 2.50 TL'), findsOneWidget);
    expect(find.text("En fazla %100'si"), findsOneWidget);
    // The default policy's own numbers must NOT leak through.
    expect(find.text('50 TL → 5 Boncuk'), findsNothing);
    expect(find.text("En fazla %50'si"), findsNothing);
  });

  testWidgets(
      'MANDATORY Fixture B (50 TL -> 3 Boncuk, 1 Boncuk = 0.50 TL, max 25%) renders correctly end-to-end, including a non-1000 progress block size',
      (tester) async {
    await pumpScreen(
      tester,
      gateway: _FakeLoyaltyGateway(
        snapshot: const LoyaltyAccountSnapshot(
          spendableBalance: 2,
          boncukDebt: 0,
          // 1700 minor units accumulated under a 5000/3 ratio: entitlement
          // floor(1700*3/5000)=1, remainder 1700-ceil(5000/3)=1700-1667=33,
          // needed = 5000/3's next threshold (3334) - 1700 = 1634.
          earningRemainderMinorUnits: 33,
          minorUnitsUntilNextBoncuk: 1634,
          lifetimeEarned: 2,
          lifetimeRedeemed: 0,
          earningSpendMinorUnits: 5000,
          earningBoncukAmount: 3,
          redemptionValueMinorUnitsPerBoncuk: 50,
          maxRedemptionBasisPoints: 2500,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // How It Works — exact fixture B economics, no rounding to a whole TL.
    expect(find.text('50 TL → 3 Boncuk'), findsOneWidget);
    expect(find.text('1 Boncuk → 0.50 TL'), findsOneWidget);
    expect(find.text("En fazla %25'si"), findsOneWidget);
    // The default policy's own numbers must never leak through.
    expect(find.text('50 TL → 5 Boncuk'), findsNothing);
    expect(find.text('1 Boncuk → 1 TL'), findsNothing);

    // Progress card — block size is 33 + 1634 = 1667 kuruş (16.67 TL, not
    // the default policy's flat 10 TL denominator), rendered exactly.
    expect(find.text('0 TL / 17 TL'), findsOneWidget);
    expect(find.textContaining('16 TL kaldı'), findsOneWidget);
  });

  testWidgets('the empty movements state sits inside a compact card',
      (tester) async {
    await pumpScreen(tester, gateway: _FakeLoyaltyGateway());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loyaltyMovementsEmptyState')), findsOneWidget);
    expect(find.text('Henüz Boncuk hareketin yok.'), findsOneWidget);
  });

  // "Profile route still opens the canonical LoyaltyScreen" is covered by
  // `test/features/profile/presentation/widgets/profile_loyalty_card_test.dart`
  // (which this P3A phase updated to import the new canonical screen) —
  // not duplicated here. "Home route still opens the canonical
  // LoyaltyScreen" is verified structurally: `home_screen.dart` imports
  // the same canonical `lib/features/loyalty/presentation/screens/
  // loyalty_screen.dart` path (confirmed by a clean `flutter analyze` —
  // a stale/wrong import would be a compile error, not a silent bug) at
  // all three of its own Boncuk entry points.
}

class _FakeLoyaltyGateway implements LoyaltyGateway {
  _FakeLoyaltyGateway({
    LoyaltyAccountSnapshot? snapshot,
    this.snapshotError,
    this.neverCompleteSnapshot = false,
    LoyaltyHistoryPage? historyPage,
  })  : snapshot = snapshot ?? LoyaltyAccountSnapshot.zero,
        historyPage = historyPage ?? LoyaltyHistoryPage.empty;

  LoyaltyAccountSnapshot snapshot;
  LoyaltyGatewayException? snapshotError;

  /// Returns a `Completer`-backed future that is deliberately never
  /// completed, to freeze the provider in its loading state for a test —
  /// unlike `Future.delayed`, this creates no pending `Timer`, so it never
  /// trips `flutter_test`'s "timer still pending after dispose" check even
  /// though the test ends before this future would ever resolve.
  bool neverCompleteSnapshot;
  LoyaltyHistoryPage historyPage;
  int snapshotCalls = 0;

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async {
    snapshotCalls += 1;
    if (neverCompleteSnapshot) {
      return Completer<LoyaltyAccountSnapshot>().future;
    }
    if (snapshotError != null) throw snapshotError!;
    return snapshot;
  }

  @override
  Future<LoyaltyHistoryPage> getHistory({int? pageSize, String? cursor}) async {
    return historyPage;
  }

  @override
  Future<List<LoyaltyReward>> getRewardCatalog() async => const [];
}
