import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_support_section.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester, {
    VoidCallback? onFeedback,
    VoidCallback? onHelp,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSupportSection(
            onFeedback: onFeedback ?? () {},
            onHelp: onHelp ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('"Destek" basligi ve gruplu kart gorunur', (tester) async {
    await pumpSection(tester);

    expect(find.text('Destek'), findsOneWidget);
    expect(find.byKey(const Key('supportCard')), findsOneWidget);
  });

  testWidgets('tam olarak Geri Bildirim + Yardım ve Destek icerir', (
    tester,
  ) async {
    await pumpSection(tester);

    expect(find.byKey(const Key('support_geriBildirim')), findsOneWidget);
    expect(find.byKey(const Key('support_yardimVeDestek')), findsOneWidget);
    expect(find.text('Geri Bildirim Gönder'), findsOneWidget);
    expect(find.text('Yardım ve Destek'), findsOneWidget);
  });

  testWidgets('her satira dokununca kendi callback tetiklenir', (
    tester,
  ) async {
    var feedbackTapped = false;
    var helpTapped = false;
    await pumpSection(
      tester,
      onFeedback: () => feedbackTapped = true,
      onHelp: () => helpTapped = true,
    );

    await tester.tap(find.byKey(const Key('support_geriBildirim')));
    await tester.tap(find.byKey(const Key('support_yardimVeDestek')));
    await tester.pumpAndSettle();

    expect(feedbackTapped, isTrue);
    expect(helpTapped, isTrue);
  });

  testWidgets('375px + 1.6x text scale altinda tasma/exception olusmaz', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: ProfileSupportSection(onFeedback: () {}, onHelp: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
