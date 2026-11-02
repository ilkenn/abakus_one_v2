import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/shared/widgets/cards/glass_card.dart';

void main() {
  testWidgets('child icerigini render eder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassCard(
            tintColor: Color(0xCC1B3B2B),
            child: Text('45 TL'),
          ),
        ),
      ),
    );

    expect(find.text('45 TL'), findsOneWidget);
  });

  testWidgets('bulanik (BackdropFilter) arka plan uygular', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassCard(
            tintColor: Color(0xCC1B3B2B),
            child: Text('Şefin Seçimi'),
          ),
        ),
      ),
    );

    final backdropFilter =
        tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdropFilter.filter, isA<ImageFilter>());
  });

  testWidgets('verilen borderRadius ile kirpilir', (tester) async {
    const radius = BorderRadius.all(Radius.circular(20));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassCard(
            tintColor: Color(0xCC1B3B2B),
            borderRadius: radius,
            child: Text('Yeni'),
          ),
        ),
      ),
    );

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, radius);
  });
}
