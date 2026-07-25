import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/data/abakus_menu_catalog.dart';
import 'package:abakus_one_v2/features/menu/domain/services/menu_image_resolver.dart';

void main() {
  group('resolve', () {
    test(
        'assets/images/menu/ altinda gercekten bulunan bir anahtar icin dogru yolu doner',
        () {
      // 'abakus-burger.png' repo icinde gercekten mevcut.
      final path = MenuImageResolver.resolve('abakus-burger');
      expect(path, 'assets/images/menu/abakus-burger.png');
    });

    test(
        'bilinmeyen/eslesmeyen bir anahtar icin null doner (yer tutucuya dusmeli)',
        () {
      final path = MenuImageResolver.resolve('bu-dosya-hic-yok');
      expect(path, isNull);
    });

    test('esleme tam ve buyuk/kucuk harf duyarlidir', () {
      // Gercek dosya 'Vegan-Bowl.png' (buyuk V), gercek menu urunu
      // 'vegan-bowl' anahtarini kullaniyor -> bilerek eslesmez.
      expect(MenuImageResolver.resolve('vegan-bowl'), isNull);
      expect(MenuImageResolver.resolve('Vegan-Bowl'), isNotNull);
    });
  });

  group('findMissingImageKeys', () {
    test('gercek menudeki eslesmeyen anahtarlari dogru raporlar', () {
      final allKeys = AbakusMenuCatalog.products.map((p) => p.imageKey);
      final missing = MenuImageResolver.findMissingImageKeys(allKeys);

      // Bilinen, isim farkindan kaynaklanan bir kac ornek: kesin var olmali.
      expect(missing, contains('ton-ton-bowl'));
      expect(missing, contains('vegan-bowl'));
      expect(missing, contains('lokum-bowl'));

      // Gercekten eslesen bir anahtar listede olmamali.
      expect(missing, isNot(contains('abakus-burger')));
    });

    test('bos girdi icin bos liste doner', () {
      expect(MenuImageResolver.findMissingImageKeys(const []), isEmpty);
    });
  });
}
