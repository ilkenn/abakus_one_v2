import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/printing/domain/turkish_ascii_transliteration.dart';

void main() {
  test('her Turkce harfi en yakin ASCII karsiligina cevirir', () {
    expect(transliterateTurkishToAscii('Çılgın Şöhret Üçlü'),
        'Cilgin Sohret Uclu');
    expect(transliterateTurkishToAscii('İstanbul'), 'Istanbul');
    expect(transliterateTurkishToAscii('ğüşiöç'), 'gusioc');
    expect(transliterateTurkishToAscii('ĞÜŞİÖÇ'), 'GUSIOC');
  });

  test('zaten ASCII olan metni degistirmeden birakir', () {
    expect(transliterateTurkishToAscii('Tavuk Bowl 123'), 'Tavuk Bowl 123');
  });

  test('bos string icin bos string doner', () {
    expect(transliterateTurkishToAscii(''), '');
  });

  test('Turkce olmayan diger Unicode karakterlere dokunmaz', () {
    expect(transliterateTurkishToAscii('café'), 'café');
  });
}
