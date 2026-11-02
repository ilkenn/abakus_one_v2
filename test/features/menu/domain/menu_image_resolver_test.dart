import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/domain/services/menu_image_resolver.dart';

void main() {
  group('resolveCandidates (2026-11-02 — per-category convention)', () {
    test('tam imageKey her zaman ilk aday olarak denenir (png ve jpg)', () {
      final candidates = MenuImageResolver.resolveCandidates(
        'general-tso',
        categoryId: 'cat_atistirmalik2',
      );
      expect(candidates.take(2), [
        'assets/images/menu/atistirmalik/general-tso.png',
        'assets/images/menu/atistirmalik/general-tso.jpg',
      ]);
    });

    test(
        "imageKey'in kendi ilk tiresinden sonraki kismi, klasor slug'i "
        "farkli olsa bile soyulur (ör. 'aperatif-' != klasor 'atistirmalik')",
        () {
      final candidates = MenuImageResolver.resolveCandidates(
        'aperatif-general-tso',
        categoryId: 'cat_atistirmalik2',
      );
      expect(candidates,
          contains('assets/images/menu/atistirmalik/general-tso.jpg'));
    });

    test(
        "imageKey product-refresh '2' ekini tasisa bile (ör. 'salata2-') "
        'soyulmus hal dogru klasore dusurulur', () {
      final candidates = MenuImageResolver.resolveCandidates(
        'salata2-veggie',
        categoryId: 'cat_salata2',
      );
      expect(candidates, contains('assets/images/menu/salata/veggie.png'));
    });

    test(
        'soyulmus govdeye klasor slug\'i SUFFIX olarak eklenmis hali de '
        "denenir (ör. bowl/<ad>-bowl.png, wrap/<ad>-wrap.png)", () {
      final bowlCandidates = MenuImageResolver.resolveCandidates(
        'bowl2-tatli-eksi-tavuk',
        categoryId: 'cat_bowl2',
      );
      expect(bowlCandidates,
          contains('assets/images/menu/bowl/tatli-eksi-tavuk-bowl.png'));

      final wrapCandidates = MenuImageResolver.resolveCandidates(
        'wrap2-asian-chicken',
        categoryId: 'cat_wrap2',
      );
      expect(wrapCandidates,
          contains('assets/images/menu/wrap/asian-chicken-wrap.png'));
    });

    test(
        "hamburger kategorisi icin 'burger' takma adi da denenir (gercek "
        "dosyalar '-hamburger' degil '-burger' suffix'i kullaniyor)", () {
      final candidates = MenuImageResolver.resolveCandidates(
        'burger2-double-chicken',
        categoryId: 'cat_hamburger2',
      );
      expect(candidates,
          contains('assets/images/menu/hamburger/double-chicken-burger.png'));
      // Klasor slug'inin kendisi de (hamburger) hala denenir — alias ekstra.
      expect(
          candidates,
          contains(
              'assets/images/menu/hamburger/double-chicken-hamburger.png'));
    });

    test('categoryId verilmezse hic aday dondurulmez', () {
      expect(MenuImageResolver.resolveCandidates('general-tso'), isEmpty);
    });

    test("categoryId gercek 'cat_' onekiyle baslamiyorsa aday dondurulmez", () {
      final candidates = MenuImageResolver.resolveCandidates(
        'general-tso',
        categoryId: 'not-a-real-category-id',
      );
      expect(candidates, isEmpty);
    });

    test('imageKey tire icermiyorsa sadece tam anahtar denenir (png/jpg)', () {
      final candidates = MenuImageResolver.resolveCandidates(
        'cocacola',
        categoryId: 'cat_icecekler',
      );
      expect(candidates, [
        'assets/images/menu/icecekler/cocacola.png',
        'assets/images/menu/icecekler/cocacola.jpg',
      ]);
    });
  });
}
