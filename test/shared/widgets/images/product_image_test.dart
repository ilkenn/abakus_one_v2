import 'dart:convert';

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
  ImageProvider? resolve(String imageKey) => resolver(imageKey);
}

void main() {
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
}
