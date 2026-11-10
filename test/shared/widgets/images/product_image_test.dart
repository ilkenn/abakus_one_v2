import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/shared/widgets/images/product_image.dart';
import 'package:abakus_one_v2/shared/widgets/images/product_image_source.dart';

/// Smallest possible valid PNG (a single transparent pixel) — lets these
/// tests exercise a real, decodable [ImageProvider] without bundling a test
/// asset.
final _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _FakeProductImageSource implements ProductImageSource {
  final ImageProvider? Function(String imageKey) resolver;

  const _FakeProductImageSource(this.resolver);

  @override
  List<ImageProvider> resolveCandidates(String imageKey, {String? categoryId}) {
    final provider = resolver(imageKey);
    return provider == null ? const [] : [provider];
  }
}

void main() {
  // 2026-11-10 — ResizeImage with BOTH width and height decodes to exactly
  // that size and squashes the photo (the product-detail hero bug). Only
  // the box's longer side may bound the decode; `BoxFit.cover` does the rest.
  testWidgets(
    'decode boyutu yalnizca kutunun uzun kenariyla sinirlanir, en-boy orani '
    'korunur ve BoxFit.cover kullanilir',
    (tester) async {
      Future<ResizeImage> pumpBox(double width, double height) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              productImageSourceProvider.overrideWithValue(
                _FakeProductImageSource((key) => MemoryImage(_tinyPngBytes)),
              ),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(devicePixelRatio: 2),
                child: Scaffold(
                  body:
                      ProductImage(imageKey: 'k', width: width, height: height),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.fit, BoxFit.cover);
        return image.image as ResizeImage;
      }

      final wide = await pumpBox(400, 320);
      expect(wide.width, 800);
      expect(wide.height, isNull);

      final tall = await pumpBox(100, 160);
      expect(tall.width, isNull);
      expect(tall.height, 320);
    },
  );

  testWidgets(
    'kaynak null donunce placeholder gosterir, gercek Image render edilmez',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productImageSourceProvider.overrideWithValue(
              _FakeProductImageSource((key) => null),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ProductImage(imageKey: 'herhangi-bir-key')),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.fastfood_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'kaynak degistiginde ProductImage kod degismeden farkli bir gorsel '
    'kaynagini render eder (gelecekte CDN/Firebase Storage gecisine hazirlik)',
    (tester) async {
      Future<void> pumpWithSource(ProductImageSource source) {
        return tester.pumpWidget(
          ProviderScope(
            overrides: [productImageSourceProvider.overrideWithValue(source)],
            child: const MaterialApp(
              home: Scaffold(
                body: ProductImage(imageKey: 'urun-1', width: 40, height: 40),
              ),
            ),
          ),
        );
      }

      await pumpWithSource(
        _FakeProductImageSource((key) => MemoryImage(_tinyPngBytes)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);

      // Ayni widget - yalnizca alttaki kaynak degisti; ProductImage'in
      // kendi kodunda hicbir satir degismedi.
      await pumpWithSource(_FakeProductImageSource((key) => null));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.fastfood_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'heroTag verildiginde Hero ile sarmalar, verilmediginde sarmalamaz',
    (tester) async {
      Future<void> pumpWithHeroTag(Object? heroTag) {
        return tester.pumpWidget(
          ProviderScope(
            overrides: [
              productImageSourceProvider.overrideWithValue(
                _FakeProductImageSource((key) => null),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ProductImage(imageKey: 'k', heroTag: heroTag),
              ),
            ),
          ),
        );
      }

      await pumpWithHeroTag(null);
      await tester.pump();
      expect(find.byType(Hero), findsNothing);

      await pumpWithHeroTag('test-tag');
      await tester.pump();
      expect(find.byType(Hero), findsOneWidget);
    },
  );

  testWidgets(
    '2026-11-02 — ilk aday (örn. henüz eklenmemiş kategori fotoğrafı) '
    'yüklenemezse, gerçek Image hâlâ İKİNCİ adaydan render edilir, '
    'yer tutucuya hiç düşmeden',
    (tester) async {
      final failingProvider = MemoryImage(Uint8List.fromList([1, 2, 3]));
      final workingProvider = MemoryImage(_tinyPngBytes);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productImageSourceProvider.overrideWithValue(
              _FakeTwoCandidateProductImageSource(
                [failingProvider, workingProvider],
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProductImage(imageKey: 'k', width: 40, height: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The failed first candidate's own `Image` element stays in the
      // tree (its `errorBuilder` result — the second candidate's `Image`
      // — becomes its child), so more than one `Image` widget legitimately
      // exists here; what actually matters is that the real photo won,
      // never the placeholder icon.
      expect(find.byType(Image), findsWidgets);
      expect(find.byIcon(Icons.fastfood_rounded), findsNothing);
    },
  );
}

class _FakeTwoCandidateProductImageSource implements ProductImageSource {
  final List<ImageProvider> candidates;
  const _FakeTwoCandidateProductImageSource(this.candidates);

  @override
  List<ImageProvider> resolveCandidates(String imageKey,
          {String? categoryId}) =>
      candidates;
}
