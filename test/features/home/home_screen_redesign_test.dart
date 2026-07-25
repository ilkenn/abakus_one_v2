import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/home/presentation/screens/home_screen.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_filter_provider.dart';
import 'package:abakus_one_v2/features/navigation/presentation/providers/navigation_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/screens/orders_screen.dart';
import 'package:abakus_one_v2/features/qr/presentation/screens/qr_scanner_screen.dart';
import 'package:abakus_one_v2/shared/widgets/images/product_image.dart';

class _AuthenticatedNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: true, isGuest: false);
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
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

  group('üst karşılama', () {
    testWidgets('saate göre selamlama gösterir, isim uydurmaz', (
      tester,
    ) async {
      await pumpHome(tester);

      const knownGreetings = [
        'Günaydın 👋',
        'İyi Günler 👋',
        'İyi Akşamlar 👋',
        'İyi Geceler 👋',
      ];
      final matches = knownGreetings.where(
        (g) => find.text(g).evaluate().isNotEmpty,
      );
      expect(matches.length, 1);
      expect(find.textContaining('Ahmet'), findsNothing);
    });

    testWidgets('sabit sube adini gosterir', (tester) async {
      await pumpHome(tester);

      expect(find.text('Abaküs Ortaköy'), findsOneWidget);
    });

    testWidgets('bildirim zilinde sahte rozet gosterilmez', (tester) async {
      await pumpHome(tester);

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.byType(Badge), findsNothing);
      expect(find.text('2'), findsNothing);
    });
  });

  group('aktif siparis', () {
    testWidgets('varsayilan aktif siparisi gosterir', (tester) async {
      await pumpHome(tester);

      expect(find.text('Aktif Siparişin'), findsOneWidget);
      expect(find.text('2x Falafel Bowl'), findsOneWidget);
    });
  });

  group('kategori kisayollari', () {
    testWidgets('gercek 7 menu kategorisini gosterir', (tester) async {
      await pumpHome(tester);

      // Kategori satiri kendi yatay Scrollable'inda - once ana dikey
      // scroll ile satira in, sonra ilk chip'in (Bowl) yatay Scrollable
      // atasini kullanarak geri kalanlari sirayla goruneme getir.
      final bowlChip = find.text('Bowl');
      await tester.dragUntilVisible(
        bowlChip,
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      final categoryRow =
          find.ancestor(of: bowlChip, matching: find.byType(Scrollable)).first;

      for (final category in [
        'Bowl',
        'Salata',
        'Wrap',
        'Hamburger',
        'Makarna',
        'Atıştırmalık',
        'İçecekler',
      ]) {
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
          const Offset(0, -300),
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

  group('kampanya alani', () {
    testWidgets('Kampanyalar basligi ve tumunu gor bagi gorunur', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('Kampanyalar'), findsOneWidget);
      expect(find.text('Tüm kampanyaları ve kuponları gör'), findsOneWidget);
    });
  });

  group('hizli aksiyonlar', () {
    testWidgets('tam olarak QR/Gel Al/Rezervasyon/Siparislerim gosterir', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('Masada QR Oku'), findsOneWidget);
      expect(find.text('Gel Al'), findsOneWidget);
      expect(find.text('Rezervasyon'), findsOneWidget);
      expect(find.text('Siparişlerim'), findsOneWidget);
      expect(find.text('Hızlı Teslimat'), findsNothing);
    });

    testWidgets('Masada QR Oku QrScannerScreen acar', (tester) async {
      await pumpHome(tester);

      await scrollToAndTap(tester, find.text('Masada QR Oku'));
      await tester.pumpAndSettle();

      expect(find.byType(QrScannerScreen), findsOneWidget);
    });

    testWidgets('Gel Al Menu sekmesini acar', (tester) async {
      await pumpHome(tester);

      await scrollToAndTap(tester, find.text('Gel Al'));
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), AppTab.menu);
    });

    testWidgets('Rezervasyon durumu acikca bildirir', (tester) async {
      await pumpHome(tester);

      await scrollToAndTap(tester, find.text('Rezervasyon'));
      await tester.pump();

      expect(
        find.text('Rezervasyon özelliği yakında eklenecek.'),
        findsOneWidget,
      );
    });

    testWidgets('Siparislerim OrdersScreen acar', (tester) async {
      await pumpHome(tester);

      await scrollToAndTap(tester, find.text('Siparişlerim'));
      await tester.pumpAndSettle();

      expect(find.byType(OrdersScreen), findsOneWidget);
    });
  });

  group('Kendi Bowlunu Yarat', () {
    testWidgets('kartina dokununca push degil, Build Bowl sekmesi aktif olur', (
      tester,
    ) async {
      await pumpHome(tester);

      final banner = find.text('Kendi Bowlunu Yarat');
      await tester.dragUntilVisible(
        banner,
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      await tester.tap(banner);
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), AppTab.buildBowl);
    });
  });

  group('populer urunler', () {
    testWidgets(
      'tek liste gosterir, Sana Ozel Lezzetler kaldirilmistir',
      (tester) async {
        await pumpHome(tester);

        expect(find.text('Popüler Ürünler'), findsOneWidget);
        expect(find.text('Sana Özel Lezzetler'), findsNothing);
      },
    );

    testWidgets('gercek urun gorselleri kullanir', (tester) async {
      await pumpHome(tester);

      final productCount = container.read(featuredMenuProductsProvider).length;
      expect(find.byType(ProductImage), findsNWidgets(productCount));
    });

    testWidgets('bos urun listesinde ekran comez', (tester) async {
      container = ProviderContainer(
        overrides: [
          featuredMenuProductsProvider.overrideWithValue(const []),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Popüler Ürünler'), findsOneWidget);
    });
  });

  group('boncuk / sadakat - guest', () {
    testWidgets('kisisel boncuk bilgisi uydurulmaz, giris CTA gosterilir', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.textContaining('Boncuk'), findsWidgets);
      expect(find.text('320 Boncuk'), findsNothing);
      expect(find.text('Boncuk kazanmaya başla'), findsOneWidget);
      expect(find.text('Bugünün Boncuk Görevleri'), findsNothing);
      expect(find.text('Boncuk Kampanyaları'), findsNothing);
    });

    testWidgets('giris yap CTA LoginScreen acar', (tester) async {
      await pumpHome(tester);

      final cta = find.text('Boncuk kazanmaya başla');
      await tester.dragUntilVisible(
        cta,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('boncuk / sadakat - authenticated', () {
    setUp(() {
      container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _AuthenticatedNotifier())],
      );
    });

    testWidgets('gercek boncuk bakiyesini gosterir', (tester) async {
      await pumpHome(tester);

      expect(find.text('320 Boncuk'), findsOneWidget);
      expect(find.text('Boncuk kazanmaya başla'), findsNothing);
    });

    testWidgets('Bugunun Boncuk Gorevleri gorev basliklarini gosterir', (
      tester,
    ) async {
      await pumpHome(tester);

      final tasksHeading = find.text('Bugünün Boncuk Görevleri');
      await tester.dragUntilVisible(
        tasksHeading,
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(tasksHeading, findsOneWidget);
      expect(find.textContaining('1 Bowl Sipariş Ver'), findsOneWidget);
    });

    testWidgets('Boncuk Kampanyalari basligini gosterir', (tester) async {
      await pumpHome(tester);

      final campaignsHeading = find.text('Boncuk Kampanyaları');
      await tester.dragUntilVisible(
        campaignsHeading,
        find.byType(Scrollable).first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();

      expect(campaignsHeading, findsOneWidget);
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
