import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/screens/bowl_builder_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/cart_screen.dart';
import 'package:abakus_one_v2/features/home/presentation/screens/home_screen.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/menu_screen.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/product_detail_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/providers/navigation_provider.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/widgets/customer_bottom_navigation.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/profile_screen.dart';
import 'package:abakus_one_v2/features/qr/presentation/screens/qr_scanner_screen.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainNavigationScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Menu tab'ının kendi görünür ürün listesinden bir kartı bulup açar -
  /// diğer sekmeler `IndexedStack` altında offstage de olsa aynı anda
  /// mount edilmiş durumda olduğu için arama `MenuScreen`'e taraflı.
  Future<void> tapMenuProductCard(
      WidgetTester tester, String productName) async {
    final finder = find.descendant(
      of: find.byType(MenuScreen),
      matching: find.text(productName),
    );
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('4 sekme + QR bottom sheet', () {
    testWidgets(
      'alt navigasyon 4 sekmeyi (Ana Sayfa, Menü, Sepetim, Profil) '
      've QR aksiyonunu gosterir',
      (tester) async {
        await pumpShell(tester);

        expect(find.text('Ana Sayfa'), findsOneWidget);
        expect(find.text('Menü'), findsOneWidget);
        expect(find.text('Sepetim'), findsOneWidget);
        expect(find.text('Profil'), findsOneWidget);
        expect(find.text('Build Bowl'), findsNothing);

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(container.read(navigationProvider), AppTab.home);
      },
    );

    testWidgets('Menü sekmesine dokununca MenuScreen gorunur olur', (
      tester,
    ) async {
      await pumpShell(tester);

      await tester.tap(find.text('Menü'));
      await tester.pumpAndSettle();

      expect(find.byType(MenuScreen), findsOneWidget);
      expect(container.read(navigationProvider), AppTab.menu);
    });

    testWidgets('Sepetim sekmesine dokununca CartScreen gorunur olur', (
      tester,
    ) async {
      await pumpShell(tester);

      await tester.tap(find.text('Sepetim'));
      await tester.pumpAndSettle();

      expect(find.byType(CartScreen), findsOneWidget);
      expect(container.read(navigationProvider), AppTab.cart);
    });

    testWidgets('Profil sekmesine dokununca ProfileScreen gorunur olur', (
      tester,
    ) async {
      await pumpShell(tester);

      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(container.read(navigationProvider), AppTab.profile);
    });

    testWidgets(
      'QR butonuna dokununca once eylem secmesi icin bottom sheet acilir, '
      'kamera dogrudan acilmaz',
      (tester) async {
        await pumpShell(tester);

        await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
        await tester.pumpAndSettle();

        expect(find.text('QR İşlemleri'), findsOneWidget);
        expect(find.text('Boncuk Kazan'), findsOneWidget);
        expect(find.text('Masada Sipariş Ver'), findsOneWidget);
        expect(find.byType(QrScannerScreen), findsNothing);
        // QR bir sekme degil, navigasyon state'i hala Ana Sayfa'da.
        expect(container.read(navigationProvider), AppTab.home);
      },
    );

    testWidgets(
      'QR sheet\'inde Masada Siparis Ver QrScannerScreen push eder, sekme '
      'degismez',
      (tester) async {
        await pumpShell(tester);

        await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Masada Sipariş Ver'));
        await tester.pumpAndSettle();

        expect(find.byType(QrScannerScreen), findsOneWidget);
        expect(container.read(navigationProvider), AppTab.home);

        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      'QR sheet\'inde Boncuk Kazan henuz hazir olmadigini acikca bildirir',
      (tester) async {
        await pumpShell(tester);

        await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Boncuk Kazan'));
        await tester.pump();

        expect(
          find.text('Bu özellik yakında eklenecek.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Bowl Builder artik bir sekme degil', () {
    testWidgets(
      'Home\'daki Kendi Bowlunu Yarat CTA\'sina dokununca push ile '
      'BowlBuilderScreen acilir, sekme degismez',
      (tester) async {
        await pumpShell(tester);

        final cta = find.text('Bowl\'unu Oluştur').first;
        await tester.dragUntilVisible(
          cta,
          find.byType(Scrollable).first,
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        await tester.tap(cta);
        await tester.pumpAndSettle();

        expect(find.byType(BowlBuilderScreen), findsOneWidget);
        expect(container.read(navigationProvider), AppTab.home);
      },
    );

    testWidgets(
      'Menu\'deki Kendi Bowlunu Yarat kartina dokununca push ile '
      'BowlBuilderScreen acilir, sekme degismez',
      (tester) async {
        await pumpShell(tester);
        await tester.tap(find.text('Menü'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Kendi Bowlunu Yarat'));
        await tester.pumpAndSettle();

        expect(find.byType(BowlBuilderScreen), findsOneWidget);
        expect(container.read(navigationProvider), AppTab.menu);
      },
    );
  });

  group('cross-tab yonlendirme', () {
    testWidgets(
      'Home\'daki hizli kategori cipine dokununca Menu sekmesi aktif olur',
      (tester) async {
        await pumpShell(tester);

        final chip = find.text('Bowl').first;
        await tester.dragUntilVisible(
          chip,
          find.byType(Scrollable).first,
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();

        expect(find.byType(MenuScreen), findsOneWidget);
        expect(container.read(navigationProvider), AppTab.menu);
      },
    );
  });

  group('state preservation', () {
    testWidgets(
      'Menu sekmesindeki arama metni baska sekmeye gecilip donulunce korunur',
      (tester) async {
        await pumpShell(tester);
        await tester.tap(find.text('Menü'));
        await tester.pumpAndSettle();

        final searchField = find.descendant(
          of: find.byType(MenuScreen),
          matching: find.byType(TextField),
        );
        await tester.enterText(searchField, 'mexi');
        await tester.pumpAndSettle();
        expect(find.text('mexi'), findsOneWidget);

        await tester.tap(find.text('Profil'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Menü'));
        await tester.pumpAndSettle();

        expect(find.text('mexi'), findsOneWidget);
      },
    );

    testWidgets(
      'bir sekmenin ic navigator stack\'i baska sekmeye gecilip donulunce korunur',
      (tester) async {
        await pumpShell(tester);
        await tester.tap(find.text('Menü'));
        await tester.pumpAndSettle();

        await tapMenuProductCard(tester, 'Mexifit Bowl');
        expect(find.byType(ProductDetailScreen), findsOneWidget);

        await tester.tap(find.text('Ana Sayfa'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);

        await tester.tap(find.text('Menü'));
        await tester.pumpAndSettle();

        expect(find.byType(ProductDetailScreen), findsOneWidget);
      },
    );
  });

  group('Android sistem geri tusu', () {
    testWidgets(
      'bir sekmenin ic stack\'inde push edilmis ekran varken geri tusu '
      'once o ekrani kapatir',
      (tester) async {
        await pumpShell(tester);
        await tester.tap(find.text('Menü'));
        await tester.pumpAndSettle();

        await tapMenuProductCard(tester, 'Mexifit Bowl');
        expect(find.byType(ProductDetailScreen), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(ProductDetailScreen), findsNothing);
        expect(find.byType(MenuScreen), findsOneWidget);
        // Ic stack'ten cikildi ama hala Menu sekmesindeyiz - Home'a atlanmadi.
        expect(container.read(navigationProvider), AppTab.menu);
      },
    );

    testWidgets(
      'Home disi bir sekmede ic stack bosken geri tusu Home sekmesine doner',
      (tester) async {
        await pumpShell(tester);
        await tester.tap(find.text('Profil'));
        await tester.pumpAndSettle();
        expect(container.read(navigationProvider), AppTab.profile);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(container.read(navigationProvider), AppTab.home);
      },
    );

    testWidgets(
      'Home sekmesinde stack bosken geri tusu shell\'in altindaki route\'a '
      'doner (uygulamadan cikis senaryosu)',
      (tester) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MainNavigationScreen(),
                        ),
                      ),
                      child: const Text('Ac'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Ac'));
        await tester.pumpAndSettle();
        expect(find.byType(MainNavigationScreen), findsOneWidget);

        // MainNavigationScreen Home sekmesinde ve stack'i bos - PopScope
        // canPop'u true birakip pop'un normal sekilde altindaki route'a
        // ilerlemesine izin vermeli (gercek uygulamada bu, Flutter'in
        // altinda baska route kalmadigi icin OS'a cikisi devretmesine denk
        // gelir).
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(MainNavigationScreen), findsNothing);
        expect(find.text('Ac'), findsOneWidget);
      },
    );
  });

  group('badge', () {
    testWidgets('sepette urun varken Sepetim rozeti dogru sayiyi gosterir', (
      tester,
    ) async {
      container.read(cartProvider.notifier).addToCart(
            id: 'test-urun-1',
            name: 'Test Ürün',
            desc: 'Test aciklama',
            price: 10,
            quantity: 3,
          );

      await pumpShell(tester);

      expect(
        find.descendant(
          of: find.byType(CustomerBottomNavigation),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sepet bosken Sepetim rozeti gosterilmez', (tester) async {
      await pumpShell(tester);

      expect(
        find.descendant(
          of: find.byType(CustomerBottomNavigation),
          matching: find.text('0'),
        ),
        findsNothing,
      );
    });
  });
}
