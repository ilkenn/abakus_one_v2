import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/domain/services/bowl_layer_image_resolver.dart';

void main() {
  test('bowl taban yolu her zaman ayni, tek bir dosyaya isaret eder', () {
    expect(
      BowlLayerImageResolver.bowlBasePath(),
      'assets/images/bowl/bowl_empty.png',
    );
  });

  test('katman yolu dogrudan imageKey uzerinden turetilir (kayit gerekmez)',
      () {
    expect(
      BowlLayerImageResolver.layerPath('izgara_tavuk'),
      'assets/images/bowl/layers/izgara_tavuk.png',
    );
    expect(
      BowlLayerImageResolver.layerPath('herhangi-bir-anahtar'),
      'assets/images/bowl/layers/herhangi-bir-anahtar.png',
    );
  });
}
