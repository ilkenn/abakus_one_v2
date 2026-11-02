import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/domain/services/menu_image_resolver.dart';

void main() {
  group('resolveCandidates (2026-11-02 — per-category convention)', () {
    test('cat_ prefix ve son "2" eki soyularak kategori klasoru kurulur', () {
      final candidates = MenuImageResolver.resolveCandidates(
        'general-tso',
        categoryId: 'cat_atistirmalik2',
      );
      expect(candidates.first, 'assets/images/menu/atistirmalik/general-tso.png');
    });

    test(
        'imageKey, kategori on-ekiyle basliyorsa on-ek soyulmus hali de IKINCI '
        'aday olarak eklenir', () {
      final candidates = MenuImageResolver.resolveCandidates(
        'kahvalti-clasico',
        categoryId: 'cat_kahvalti',
      );
      expect(candidates, [
        'assets/images/menu/kahvalti/kahvalti-clasico.png',
        'assets/images/menu/kahvalti/clasico.png',
      ]);
    });

    test('imageKey kategori on-ekiyle baslamiyorsa sadece tam anahtar denenir',
        () {
      final candidates = MenuImageResolver.resolveCandidates(
        'general-tso',
        categoryId: 'cat_atistirmalik2',
      );
      expect(candidates, ['assets/images/menu/atistirmalik/general-tso.png']);
    });

    test('categoryId verilmezse hic aday dondurulmez', () {
      expect(MenuImageResolver.resolveCandidates('general-tso'), isEmpty);
    });

    test("categoryId gercek 'cat_' onekiyle baslamiyorsa aday dondurulmez",
        () {
      final candidates = MenuImageResolver.resolveCandidates(
        'general-tso',
        categoryId: 'not-a-real-category-id',
      );
      expect(candidates, isEmpty);
    });
  });
}
