import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/core/theme/app_spacing.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/screens/bowl_builder_screen.dart';
import 'package:abakus_one_v2/features/campaigns/presentation/screens/campaigns_screen.dart';
import 'package:abakus_one_v2/features/delivery/presentation/screens/delivery_address_selection_screen.dart';
import 'package:abakus_one_v2/features/home/presentation/screens/home_screen.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/community_preview_section.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/compact_bowl_builder_card.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/featured_content_section.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/home_section_title.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/home_top_bar.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/popular_products_section.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/weekly_editorial_section.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_filter_provider.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/product_detail_screen.dart';
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
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/screens/loyalty_screen.dart';
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

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        // The canonical LoyaltyScreen (P3A) is real/server-authoritative —
        // a fake gateway keeps this navigation-focused suite from ever
        // touching the real (uninitialized-in-test) Firebase SDK.
        loyaltyGatewayProvider.overrideWithValue(const _FakeLoyaltyGateway()),
      ],
    );
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

    testWidgets(
        'basliktaki Boncuk eylemi uydurulmus sayi gostermez, LoyaltyScreen '
        'acar (H.1.1 header mock-Boncuk duzeltmesi)', (tester) async {
      container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _AuthenticatedNotifier())],
      );
      addTearDown(container.dispose);

      await pumpHome(tester);

      // No numeric balance anywhere on Home at all now — neither the old
      // BoncukBalancePill's "320" nor any other fabricated number.
      expect(find.text('320'), findsNothing);
      expect(find.text('320 Boncuk'), findsNothing);
      expect(find.text('Boncuklarım'), findsOneWidget);

      await tester.tap(find.text('Boncuklarım'));
      await tester.pumpAndSettle();

      expect(find.byType(LoyaltyScreen), findsOneWidget);
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

  group('3. hero carousel (H.2)', () {
    testWidgets('tam olarak 3 slayt yapilandirilmistir', (tester) async {
      await pumpHome(tester);

      final indicator = find.descendant(
        of: find.byKey(const Key('heroCarouselIndicator')),
        matching: find.byType(AnimatedContainer),
      );
      expect(indicator, findsNWidgets(3));
    });

    testWidgets('banner_01 CTA hedefi CampaignsScreen\'i acar', (
      tester,
    ) async {
      await pumpHome(tester);

      final cta = find.byKey(const Key('heroCta_banner_01.png'));
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(CampaignsScreen), findsOneWidget);
    });

    testWidgets('banner_02 CTA hedefi LoyaltyScreen\'i acar', (tester) async {
      await pumpHome(tester);

      final pageView = find.byKey(const Key('homeHeroCarousel'));
      await tester.ensureVisible(pageView);
      await tester.pumpAndSettle();
      await tester.fling(pageView, const Offset(-400, 0), 800);
      await tester.pumpAndSettle();

      final cta = find.byKey(const Key('heroCta_banner_02.png'));
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(LoyaltyScreen), findsOneWidget);
    });

    testWidgets('banner_04 CTA hedefi DeliveryAddressSelectionScreen\'i acar',
        (tester) async {
      await pumpHome(tester);

      final pageView = find.byKey(const Key('homeHeroCarousel'));
      await tester.ensureVisible(pageView);
      await tester.pumpAndSettle();
      await tester.fling(pageView, const Offset(-400, 0), 800);
      await tester.pumpAndSettle();
      await tester.fling(pageView, const Offset(-400, 0), 800);
      await tester.pumpAndSettle();

      final cta = find.byKey(const Key('heroCta_banner_04.png'));
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(DeliveryAddressSelectionScreen), findsOneWidget);
    });

    testWidgets(
        'telefon genisliginde mobil kompozisyon kullanilir — gercek '
        'Flutter baslik/CTA, tam boy sanat eseri yerine', (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpHome(tester);

      // Real Flutter text — not baked into the artwork, so it can never
      // render illegibly small or get clipped the way H.2's full-artwork
      // scale-down did.
      expect(find.text('İlk Siparişine 100 TL Bizden'), findsOneWidget);
      expect(find.text('Fırsatı Kullan'), findsOneWidget);

      final cta = find.byKey(const Key('heroCta_banner_01.png'));
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(CampaignsScreen), findsOneWidget);
    });
  });

  group('4. siparis modu bolumu (H.2 — kompakt 2x2 grid)', () {
    testWidgets(
      'tam olarak Masada Siparis/Gel Al/Paket Servis/Rezervasyon gosterir, '
      'hepsi kaydirmadan ayni anda gorunur',
      (tester) async {
        await pumpHome(tester);

        expect(find.text('Nasıl sipariş vermek istersin?'), findsOneWidget);

        final grid = find.byKey(const Key('orderModeGrid'));
        await tester.ensureVisible(grid);
        await tester.pumpAndSettle();

        for (final label in [
          'Masada Sipariş',
          'Gel Al',
          'Paket Servis',
          'Rezervasyon',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
      },
    );

    testWidgets('Masada Siparis QrScannerScreen acar', (tester) async {
      await pumpHome(tester);

      await scrollToAndTap(tester, find.text('Masada Sipariş'));
      await tester.pumpAndSettle();

      expect(find.byType(QrScannerScreen), findsOneWidget);
    });

    testWidgets(
        'Gel Al TakeawayBranchSelectionScreen acar (Faz C — artik Menu '
        'sekmesine degil, sube secimi/giris kontrolune yonlendirir)',
        (tester) async {
      await pumpHome(tester);

      await scrollToAndTap(tester, find.text('Gel Al'));
      await tester.pumpAndSettle();

      expect(find.byType(TakeawayBranchSelectionScreen), findsOneWidget);
    });

    testWidgets('Paket Servis Menu sekmesini acar', (tester) async {
      await pumpHome(tester);

      await scrollToAndTap(tester, find.text('Paket Servis'));
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), AppTab.menu);
    });

    testWidgets(
        'Rezervasyon kartina basmak gercek rezervasyon akisini acar (coming-soon SnackBar artik yok)',
        (tester) async {
      await pumpHome(tester);

      await scrollToAndTap(tester, find.text('Rezervasyon'));
      await tester.pumpAndSettle();

      expect(
          find.text('Rezervasyon özelliği yakında eklenecek.'), findsNothing);
      expect(find.text('Reservation Flow Route'), findsOneWidget);
    });
  });

  group('5. Kendi Bowl\'unu Yarat (H.2 — tek konsolide promo)', () {
    testWidgets('Home\'da tam olarak TEK Bowl Builder promosu bulunur', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.byType(CompactBowlBuilderCard), findsOneWidget);
    });

    testWidgets('kartina dokununca push ile BowlBuilderScreen acilir', (
      tester,
    ) async {
      await pumpHome(tester);

      final cta = find.descendant(
        of: find.byType(CompactBowlBuilderCard),
        matching: find.text('Bowl\'unu Oluştur'),
      );
      await scrollToAndTap(tester, cta);
      await tester.pumpAndSettle();

      expect(find.byType(BowlBuilderScreen), findsOneWidget);
    });
  });

  group('6. one cikan icerik (H.2 — bilincli olarak Home\'dan cikarildi)', () {
    // H.2: the hero carousel now owns the primary-promotion role
    // FeaturedContentSection used to play on Home; showing both would
    // duplicate campaign messaging (locked instruction). The widget/
    // provider itself is untouched (`featured_content_section.dart`,
    // `campaignsProvider`) — only Home's own reference to it was removed,
    // so this section's own dedicated behavior tests (active campaigns
    // render, empty state hides the section) no longer apply to *Home*
    // and were removed rather than left asserting now-false behavior; this
    // single test documents/guards the deliberate omission instead.
    testWidgets('FeaturedContentSection artik Home agacinda render edilmez', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.byType(FeaturedContentSection), findsNothing);
    });
  });

  group('7. Abaküs\'ün Favorileri (H.2 rename/reframe)', () {
    testWidgets('Abakusun Favorileri basligini gosterir', (tester) async {
      await pumpHome(tester);

      expect(find.text('Abaküs\'ün Favorileri'), findsOneWidget);
      // Eski baslik artik hicbir yerde gorunmuyor.
      expect(find.text('En Sevilen Bowl\'lar'), findsNothing);
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
      expect(find.text('Abaküs\'ün Favorileri'), findsNothing);
    });

    testWidgets(
        'kart yuksekligi kompakttir, altinda bosluk birakmaz (H.2.1 dead '
        'space regresyon korumasi)', (tester) async {
      await pumpHome(tester);

      final card = find
          .descendant(
            of: find.byType(PopularProductsSection),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.dragUntilVisible(
        card,
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      // H.2's first pass used 292 (with the image fixed at 136, leaving a
      // large unused strip below the price) — this caps it well below
      // that regression threshold. Not a pixel-exact assertion since the
      // card's Expanded image absorbs any small future adjustment safely.
      final cardHeight = tester.getSize(card).height;
      expect(cardHeight, lessThanOrEqualTo(230));
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
    testWidgets(
        'kisisel boncuk bilgisi uydurulmaz, ayni premium karti gosterir '
        '(H.2.3 — eski settings-row satiri artik yok)', (tester) async {
      await pumpHome(tester);

      expect(find.text('320 Boncuk'), findsNothing);
      // Eski settings-row metni artik hicbir zaman gorunmuyor — misafir
      // de authenticated ile ayni premium karti goruyor.
      expect(find.text('Boncuk kazanmaya başla'), findsNothing);
      expect(find.text('Boncuklarını Biriktirmeye Başla'), findsOneWidget);
      expect(
        find.text('Her uygun siparişinle Boncuk kazan, ödüllere yaklaş.'),
        findsOneWidget,
      );
      expect(find.text('Boncukları Keşfet'), findsOneWidget);
    });

    testWidgets('CTA LoginScreen acar (misafir henuz giris yapmadi)', (
      tester,
    ) async {
      await pumpHome(tester);

      final cta = find.text('Boncukları Keşfet');
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
        'mock loyaltyProvider bakiyesi/ilerlemesi gercek musteri verisi '
        'gibi gosterilmez — premium sifir/baslamamis durum gosterilir '
        '(H.1.1 loyalty mock-data duzeltmesi)', (tester) async {
      await pumpHome(tester);

      // The exact strings this correction removed — proves the mock
      // loyaltyProvider seed (balance 320, bronze->silver gap 680) can
      // never leak onto Home as if it were real customer state, not just
      // that *some* text changed.
      expect(find.text('320 Boncuk'), findsNothing);
      expect(find.textContaining('680 Boncuk sonra'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      expect(find.text('Boncuklarını Biriktirmeye Başla'), findsOneWidget);
      expect(
        find.text('Her uygun siparişinle Boncuk kazan, ödüllere yaklaş.'),
        findsOneWidget,
      );
      expect(find.text('Boncuk kazanmaya başla'), findsNothing);
      // H.2.1: the section now shows a real compact CTA button instead of
      // a bare chevron affordance.
      expect(find.text('Boncukları Keşfet'), findsOneWidget);
    });

    testWidgets('CTA canonical LoyaltyScreen\'i acar', (tester) async {
      await pumpHome(tester);

      final cta = find.text('Boncukları Keşfet');
      await tester.dragUntilVisible(
        cta,
        find.byType(Scrollable).first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();

      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(LoyaltyScreen), findsOneWidget);
    });
  });

  group('10. Topluluk & Yorumlar (H.2 — henuz gercek veri yok)', () {
    testWidgets('bolum basligi ve "Yakinda" ibaresi gorunur', (tester) async {
      await pumpHome(tester);

      final section = find.byType(CommunityPreviewSection);
      await tester.dragUntilVisible(
        section,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Topluluk & Yorumlar'), findsOneWidget);
      expect(
        find.descendant(of: section, matching: find.text('Yakında')),
        findsOneWidget,
      );
    });

    testWidgets(
        'baslik tam metin olarak gorunur, kirpilmis banner paneli olarak '
        'degil (H.2.1 — H.2\'nin kirpilmis versiyonunun duzeltmesi)',
        (tester) async {
      await pumpHome(tester);

      final section = find.byType(CommunityPreviewSection);
      await tester.dragUntilVisible(
        section,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      // Real Flutter Text, so it renders in full or not at all — never
      // visibly cut off the way the old cropped-artwork panel was.
      expect(
        find.descendant(
          of: section,
          matching: find.text('Gerçek Yorumlar, Gerçek Lezzetler'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'banner_05 icindeki uydurma yorumcu adlari/puanlari/CTA metni Home '
        'agacinda gercek Text olarak yer almaz', (tester) async {
      await pumpHome(tester);

      final section = find.byType(CommunityPreviewSection);
      await tester.dragUntilVisible(
        section,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      for (final fabricated in [
        'Ece K.',
        'Mert A.',
        'Selen Y.',
        'Yorumları Keşfet',
        'BİNLERCE MUTLU MÜŞTERİ',
      ]) {
        expect(find.text(fabricated), findsNothing, reason: fabricated);
      }
    });
  });

  group('11. Bu Hafta Abaküs\'te (H.2 — gercek urun verisi)', () {
    testWidgets('gercek bir urunun adini/fiyatini gosterir', (tester) async {
      await pumpHome(tester);

      final section = find.byType(WeeklyEditorialSection);
      await tester.dragUntilVisible(
        section,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      final spotlightProduct =
          container.read(featuredMenuProductsProvider).last;
      expect(find.text(spotlightProduct.name), findsOneWidget);
      expect(
        find.text('${spotlightProduct.basePrice.toStringAsFixed(0)} TL'),
        findsOneWidget,
      );
    });

    testWidgets('dokununca ProductDetailScreen acar', (tester) async {
      await pumpHome(tester);

      final spotlightProduct =
          container.read(featuredMenuProductsProvider).last;
      final card = find.ancestor(
        of: find.text(spotlightProduct.name),
        matching: find.byType(WeeklyEditorialSection),
      );
      await tester.dragUntilVisible(
        card,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(spotlightProduct.name));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
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

  group('H.1 premium header + responsive shell', () {
    testWidgets(
        'bildirim zili gercek olmayan bir sayi/badge ile suslenmez '
        '(unreadNotificationsCountProvider hala mock)', (tester) async {
      await pumpHome(tester);

      // Home never uses Badge anywhere else in its own tree (the cart
      // count Badge lives in CustomerBottomNavigation, a sibling shell
      // widget this harness doesn't pump) — so zero Badge instances here
      // is a precise signal, not a coincidence.
      expect(find.byType(Badge), findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    });

    testWidgets(
        'telefon genisliginde tek sutunlu kalir, tasma/exception olusmaz',
        (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpHome(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Abaküs Ortaköy'), findsOneWidget);
    });

    testWidgets(
        'genis (tablet/web) ekranda icerik tam genisliğe uzamaz, '
        'okunabilir bir maksimum genislikte kalir', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpHome(tester);

      final headerWidth = tester.getSize(find.byType(HomeTopBar)).width;
      // Constrained content max width (640) plus the screen's own
      // horizontal padding (AppSpacing.xl = 24 on each side) — well short
      // of the 1200-wide viewport, proving the cap is actually applied
      // rather than merely present in source.
      expect(headerWidth, lessThanOrEqualTo(640 + AppSpacing.xl * 2));
    });
  });

  group('H.1.1 gorsel yeniden tasarim', () {
    testWidgets(
        'bolum basliklari ortak HomeSectionTitle bileseniyle tutarli '
        'gosterilir (siparis modu, kategoriler, populer urunler)',
        (tester) async {
      await pumpHome(tester);

      // At least the always-visible sections use the shared title widget
      // — a structural guarantee of consistent title typography/spacing
      // across sections, not just a visual convention every section
      // happens to follow independently.
      expect(find.byType(HomeSectionTitle), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(HomeSectionTitle),
          matching: find.text('Nasıl sipariş vermek istersin?'),
        ),
        findsOneWidget,
      );
    });

    // Superseded by "9. boncuk - authenticated"'s own H.1.1 test above,
    // which now asserts the opposite of what this test originally checked
    // — [loyaltyProvider]'s mock balance/progress must never render on
    // Home as real customer state (see `boncuk_section.dart`'s class doc
    // comment for the full correction).
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

  @override
  Future<List<LoyaltyReward>> getRewardCatalog() async => const [];
}
