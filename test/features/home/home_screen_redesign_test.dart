import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/screens/bowl_builder_screen.dart';
import 'package:abakus_one_v2/features/campaigns/domain/models/campaign_model.dart';
import 'package:abakus_one_v2/features/campaigns/presentation/providers/campaigns_provider.dart';
import 'package:abakus_one_v2/features/home/presentation/screens/home_screen.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/build_bowl_banner.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/home_hero_section.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_filter_provider.dart';
import 'package:abakus_one_v2/features/navigation/presentation/providers/navigation_provider.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/screens/qr_scanner_screen.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/screens/takeaway_branch_selection_screen.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:abakus_one_v2/shared/widgets/images/product_image.dart';

/// Carries a real [AuthSession] (uid `'uid-1'`) — Phase 9K: the canonical
/// customer-orders read path (`OrdersNotifier.build`) keys off
/// `AuthState.session.uid`, not just `isAuthenticated`, so any test relying
/// on order/loyalty data being scoped to a signed-in user needs a real
/// session, not just the boolean.
class _AuthenticatedNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: 'uid-1',
          phoneNumber: '+905321234567',
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        ),
      );
}

class _EmptyCampaignsNotifier extends CampaignsNotifier {
  @override
  List<CampaignModel> build() => const [];
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  Future<void> pumpHome(WidgetTester tester) async {
    // Faz R.2 — `HomeScreen`'s reservation card now navigates via
    // `context.push(AppRoutes.reservationPrefix)` (a real go_router
    // destination, so the URL/location stays in sync — unlike every other
    // order-mode card, which still uses raw `Navigator.push`). This test
    // file's own harness needs a real `GoRouter` ancestor for that one
    // button; every other test here keeps working identically, since raw
    // `Navigator.push` behaves the same regardless of how the app root is
    // configured. The `/reservation` route renders a minimal marker
    // screen, not the real `ReservationFlowScreen` — this file is testing
    // Home's own navigation wiring, not the reservation feature itself
    // (which has its own dedicated tests, including a real Firebase-backed
    // provider this harness doesn't set up).
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: AppRoutes.reservationPrefix,
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Reservation Flow Route')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the outer vertical page scroll (not any of the nested
  /// horizontal lists) until [finder] is visible, then taps it.
  Future<void> scrollToAndTap(WidgetTester tester, Finder finder) async {
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  /// The order-mode cards are wide (~75% of screen width) and live inside
  /// their own horizontal `ListView`, which — like any lazily-built
  /// `ListView` — only mounts cards within its viewport/cache extent. The
  /// first card ("Masada Sipariş") is always reachable via the outer
  /// vertical scroll; this then finds *that* horizontal `Scrollable`
  /// specifically and drags it to reveal a later card, mirroring the same
  /// two-step pattern the category tests already use for their own
  /// horizontal list.
  Future<void> scrollOrderModeCardAndTap(
    WidgetTester tester,
    String label,
  ) async {
    final firstCard = find.text('Masada Sipariş');
    await tester.ensureVisible(firstCard);
    await tester.pumpAndSettle();

    if (label != 'Masada Sipariş') {
      // Deriving the Scrollable from `firstCard`'s ancestor breaks once
      // enough leftward drags scroll the first card itself out of the lazy
      // list's cache extent (it unmounts). The list's own `Key` stays valid
      // for the whole scroll regardless of which children are mounted.
      final orderModeRow = find.byKey(const Key('orderModeListView'));
      final target = find.text(label);
      // The order-mode row (~415px tall in this test viewport) is taller
      // than fits comfortably below the rest of the page content, so after
      // the vertical `ensureVisible` above, the row's own *center* point
      // (what `drag()`/`dragUntilVisible()` target by default) can fall
      // above y=0 — off-screen — even though part of the row is genuinely
      // visible. Dragging from an explicit point inside the row/viewport
      // intersection sidesteps that instead of relying on the row's center.
      var attempts = 0;
      while (target.evaluate().isEmpty && attempts < 10) {
        final rowRect = tester.getRect(orderModeRow);
        final viewport =
            tester.view.physicalSize / tester.view.devicePixelRatio;
        final startY = ((rowRect.top.clamp(0.0, viewport.height) +
                rowRect.bottom.clamp(0.0, viewport.height)) /
            2);
        await tester.dragFrom(Offset(400, startY), const Offset(-300, 0));
        await tester.pumpAndSettle();
        attempts++;
      }
    }

    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
  }

  group('1. compact top bar', () {
    testWidgets('sabit sube adini ve kompakt acik/kapali durumunu gosterir', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('Abaküs Ortaköy'), findsOneWidget);
      expect(find.text('Açık'), findsOneWidget);
    });

    testWidgets('eski buyuk sube karti ve teslimat bilgisi kaldirilmistir', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.textContaining('dk'), findsNothing);
      expect(find.text('Yoğun'), findsNothing);
    });

    testWidgets('bildirim ikonu gorunur', (tester) async {
      await pumpHome(tester);

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    });
  });

  group('2. aktif siparis banner', () {
    setUp(() {
      container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _AuthenticatedNotifier())],
      );
    });

    testWidgets('gercek aktif siparis varsa kompakt banner gosterir', (
      tester,
    ) async {
      final line = OrderLine.create(
        productId: 'prod_falafel_bowl',
        productName: 'Falafel Bowl',
        quantity: 2,
        unitPrice: Money.fromLegacyDoubleTry(132.5),
        taxRate: TaxPolicy.defaultRate,
      );
      final order = Order(
        id: OrderId('order-active-1'),
        orderNumber: OrderNumber('A-100'),
        status: OrderStatus.preparing,
        channel: OrderChannel.delivery,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        customerId: 'uid-1',
        lines: [line],
        pricing: PriceCalculator.calculate(
          lines: [line],
          currency: Currency.tryLira,
        ),
        timestamps: OrderTimestamps(created: DateTime(2026, 7, 20)),
      );
      await container.read(canonicalOrderRepositoryProvider).submitOrder(order);

      await pumpHome(tester);

      expect(find.textContaining('2x Falafel Bowl'), findsOneWidget);
    });

    testWidgets('aktif siparis yoksa banner gosterilmez', (tester) async {
      await pumpHome(tester);

      // "Falafel Bowl" tek basina kontrol edilemez - gercek katalogda
      // zaten featured bir urun olarak Populer Urunler'de goruntuleniyor.
      // Aktif siparis banner'ina ozgu "2x ..." formatinin yoklugunu kontrol
      // ediyoruz.
      expect(find.textContaining('2x Falafel Bowl'), findsNothing);
    });
  });

  group('3. hero', () {
    testWidgets('ana mesaj, alt mesaj ve CTA gosterir', (tester) async {
      await pumpHome(tester);

      expect(
        find.descendant(
          of: find.byType(HomeHeroSection),
          matching: find.text('Kendi Bowl\'unu Yarat'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(HomeHeroSection),
          matching: find.text('Bowl\'unu Oluştur'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('CTA BowlBuilderScreen\'i push eder', (tester) async {
      await pumpHome(tester);

      final cta = find.descendant(
        of: find.byType(HomeHeroSection),
        matching: find.text('Bowl\'unu Oluştur'),
      );
      await tester.dragUntilVisible(
        cta,
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(BowlBuilderScreen), findsOneWidget);
    });
  });

  group('4. siparis modu bolumu', () {
    testWidgets(
      'tam olarak Masada Siparis/Gel Al/Paket Servis/Rezervasyon gosterir',
      (tester) async {
        await pumpHome(tester);

        expect(find.text('Nasıl sipariş vermek istersin?'), findsOneWidget);

        final firstCard = find.text('Masada Sipariş');
        await tester.ensureVisible(firstCard);
        await tester.pumpAndSettle();
        expect(firstCard, findsOneWidget);

        final orderModeRow = find.byKey(const Key('orderModeListView'));
        for (final label in ['Gel Al', 'Paket Servis', 'Rezervasyon']) {
          final target = find.text(label);
          var attempts = 0;
          while (target.evaluate().isEmpty && attempts < 10) {
            final rowRect = tester.getRect(orderModeRow);
            final viewport =
                tester.view.physicalSize / tester.view.devicePixelRatio;
            final startY = ((rowRect.top.clamp(0.0, viewport.height) +
                    rowRect.bottom.clamp(0.0, viewport.height)) /
                2);
            await tester.dragFrom(Offset(400, startY), const Offset(-300, 0));
            await tester.pumpAndSettle();
            attempts++;
          }
          expect(target, findsOneWidget, reason: label);
        }
      },
    );

    testWidgets('Masada Siparis QrScannerScreen acar', (tester) async {
      await pumpHome(tester);

      await scrollOrderModeCardAndTap(tester, 'Masada Sipariş');
      await tester.pumpAndSettle();

      expect(find.byType(QrScannerScreen), findsOneWidget);
    });

    testWidgets(
        'Gel Al TakeawayBranchSelectionScreen acar (Faz C — artik Menu '
        'sekmesine degil, sube secimi/giris kontrolune yonlendirir)',
        (tester) async {
      await pumpHome(tester);

      await scrollOrderModeCardAndTap(tester, 'Gel Al');
      await tester.pumpAndSettle();

      expect(find.byType(TakeawayBranchSelectionScreen), findsOneWidget);
    });

    testWidgets('Paket Servis Menu sekmesini acar', (tester) async {
      await pumpHome(tester);

      await scrollOrderModeCardAndTap(tester, 'Paket Servis');
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), AppTab.menu);
    });

    testWidgets(
        'Rezervasyon kartina basmak gercek rezervasyon akisini acar (coming-soon SnackBar artik yok)',
        (tester) async {
      await pumpHome(tester);

      await scrollOrderModeCardAndTap(tester, 'Rezervasyon');
      await tester.pumpAndSettle();

      expect(
          find.text('Rezervasyon özelliği yakında eklenecek.'), findsNothing);
      expect(find.text('Reservation Flow Route'), findsOneWidget);
    });
  });

  group('5. Bowl Builder banner', () {
    testWidgets('baslik, alt baslik ve CTA gosterir', (tester) async {
      await pumpHome(tester);

      expect(
        find.descendant(
          of: find.byType(BuildBowlBanner),
          matching: find.text(
            'Malzemeni seç, fiyatını anında gör. Tamamen sana özel hazırla.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('kartina dokununca push ile BowlBuilderScreen acilir', (
      tester,
    ) async {
      await pumpHome(tester);

      final cta = find.descendant(
        of: find.byType(BuildBowlBanner),
        matching: find.text('Bowl\'unu Oluştur'),
      );
      await scrollToAndTap(tester, cta);
      await tester.pumpAndSettle();

      expect(find.byType(BowlBuilderScreen), findsOneWidget);
    });
  });

  group('6. one cikan icerik', () {
    testWidgets('gercek aktif kampanyalari gosterir', (tester) async {
      await pumpHome(tester);

      final activeCampaigns =
          container.read(campaignsProvider).where((c) => c.isActive);
      expect(activeCampaigns, isNotEmpty);
      for (final campaign in activeCampaigns) {
        await tester.dragUntilVisible(
          find.text(campaign.title),
          find.byType(Scrollable).first,
          const Offset(0, -300),
        );
        expect(find.text(campaign.title), findsOneWidget);
      }
    });

    testWidgets('gercek kampanya yoksa bolum tamamen gizlenir', (
      tester,
    ) async {
      container = ProviderContainer(
        overrides: [
          campaignsProvider.overrideWith(() => _EmptyCampaignsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await pumpHome(tester);

      expect(find.text('Öne Çıkanlar'), findsNothing);
    });
  });

  group('7. populer urunler', () {
    testWidgets('En Sevilen Bowllar basligini gosterir', (tester) async {
      await pumpHome(tester);

      expect(find.text('En Sevilen Bowl\'lar'), findsOneWidget);
    });

    testWidgets('gercek urun gorselleri kullanir', (tester) async {
      await pumpHome(tester);

      // Yatay ListView.builder viewport disindaki kartlari lazy olarak
      // insa etmez (dogru/beklenen davranis) - tam sayi yerine en az bir
      // gercek ProductImage'in render edildigini dogruluyoruz.
      expect(find.byType(ProductImage), findsWidgets);
    });

    testWidgets('bos urun listesinde bolum gizlenir, ekran comez', (
      tester,
    ) async {
      container = ProviderContainer(
        overrides: [
          featuredMenuProductsProvider.overrideWithValue(const []),
        ],
      );
      addTearDown(container.dispose);

      await pumpHome(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('En Sevilen Bowl\'lar'), findsNothing);
    });
  });

  group('8. kategoriler', () {
    testWidgets('gercek 7 kategoriyi tam istenen sirada gosterir', (
      tester,
    ) async {
      await pumpHome(tester);

      final bowlChip = find.text('Bowl');
      await tester.dragUntilVisible(
        bowlChip,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      final categoryRow =
          find.ancestor(of: bowlChip, matching: find.byType(Scrollable)).first;

      const expectedOrder = [
        'Bowl',
        'Salata',
        'Wrap',
        'Hamburger',
        'Makarna',
        'Atıştırmalık',
        'İçecekler',
      ];
      for (final category in expectedOrder) {
        await tester.dragUntilVisible(
          find.text(category),
          categoryRow,
          const Offset(-150, 0),
        );
        await tester.pumpAndSettle();
        expect(find.text(category), findsOneWidget, reason: category);
      }
    });

    testWidgets(
      'kategoriye dokununca Menu sekmesi aktif olur ve filtre aktarilir',
      (tester) async {
        await pumpHome(tester);

        final bowlChip = find.text('Bowl');
        await tester.dragUntilVisible(
          bowlChip,
          find.byType(Scrollable).first,
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();

        final categoryRow = find
            .ancestor(of: bowlChip, matching: find.byType(Scrollable))
            .first;
        final hamburgerChip = find.text('Hamburger');
        await tester.dragUntilVisible(
          hamburgerChip,
          categoryRow,
          const Offset(-150, 0),
        );
        await tester.pumpAndSettle();

        await tester.tap(hamburgerChip);
        await tester.pumpAndSettle();

        expect(container.read(menuFilterProvider), 'Hamburger');
        expect(container.read(navigationProvider), AppTab.menu);
      },
    );
  });

  group('9. boncuk - guest', () {
    testWidgets('kisisel boncuk bilgisi uydurulmaz, giris CTA gosterilir', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('320 Boncuk'), findsNothing);
      expect(find.text('Boncuk kazanmaya başla'), findsOneWidget);
    });

    testWidgets('giris yap CTA LoginScreen acar', (tester) async {
      await pumpHome(tester);

      final cta = find.text('Boncuk kazanmaya başla');
      await tester.dragUntilVisible(
        cta,
        find.byType(Scrollable).first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();

      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('9. boncuk - authenticated', () {
    setUp(() {
      container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _AuthenticatedNotifier())],
      );
    });

    testWidgets(
        'gercek boncuk bakiyesini gosterir, Bowl Builder\'dan '
        'daha sade kalir', (tester) async {
      await pumpHome(tester);

      expect(find.text('320 Boncuk'), findsOneWidget);
      expect(find.text('Boncuk kazanmaya başla'), findsNothing);
    });
  });

  group('erisilebilirlik / responsive', () {
    testWidgets('buyuk text scale ile tasma/exception olusmaz', (
      tester,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(1.6),
            ),
            child: MaterialApp(home: HomeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
