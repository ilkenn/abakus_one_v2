import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_account_preferences_section.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester, {
    VoidCallback? onAddresses,
    VoidCallback? onPaymentMethods,
    VoidCallback? onNotificationSettings,
    VoidCallback? onAccountData,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileAccountPreferencesSection(
              onAddresses: onAddresses ?? () {},
              onPaymentMethods: onPaymentMethods ?? () {},
              onNotificationSettings: onNotificationSettings ?? () {},
              onAccountData: onAccountData ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('"Hesap & Tercihler" basligi ve gruplu kart gorunur', (
    tester,
  ) async {
    await pumpSection(tester);

    expect(find.text('Hesap & Tercihler'), findsOneWidget);
    expect(find.byKey(const Key('accountPreferencesCard')), findsOneWidget);
  });

  testWidgets(
      'tam olarak 4 kilitli hesap/tercih hedefi bu grup altinda '
      'listelenir', (tester) async {
    await pumpSection(tester);

    expect(find.byKey(const Key('pref_adreslerim')), findsOneWidget);
    expect(find.byKey(const Key('pref_odemeYontemlerim')), findsOneWidget);
    expect(find.byKey(const Key('pref_bildirimAyarlari')), findsOneWidget);
    expect(find.byKey(const Key('pref_hesapVeVerilerim')), findsOneWidget);
    expect(find.text('Adreslerim'), findsOneWidget);
    expect(find.text('Ödeme Yöntemlerim'), findsOneWidget);
    expect(find.text('Bildirim Ayarları'), findsOneWidget);
    expect(find.text('Hesap ve Verilerim'), findsOneWidget);
  });

  testWidgets('her satira dokununca kendi callback tetiklenir', (
    tester,
  ) async {
    var addressesTapped = false;
    var paymentTapped = false;
    var notificationsTapped = false;
    var accountDataTapped = false;
    await pumpSection(
      tester,
      onAddresses: () => addressesTapped = true,
      onPaymentMethods: () => paymentTapped = true,
      onNotificationSettings: () => notificationsTapped = true,
      onAccountData: () => accountDataTapped = true,
    );

    await tester.tap(find.byKey(const Key('pref_adreslerim')));
    await tester.tap(find.byKey(const Key('pref_odemeYontemlerim')));
    await tester.tap(find.byKey(const Key('pref_bildirimAyarlari')));
    await tester.tap(find.byKey(const Key('pref_hesapVeVerilerim')));
    await tester.pumpAndSettle();

    expect(addressesTapped, isTrue);
    expect(paymentTapped, isTrue);
    expect(notificationsTapped, isTrue);
    expect(accountDataTapped, isTrue);
  });

  testWidgets('sahte odeme karti verisi (numara/sahip adi) gostermez', (
    tester,
  ) async {
    await pumpSection(tester);

    // Bu widget navigasyon disinda hicbir veri render etmiyor — kart
    // numarasi/sahip adi gibi hicbir odeme bilgisi burada yok.
    expect(find.textContaining('4321'), findsNothing);
    expect(find.textContaining('5678'), findsNothing);
    expect(find.textContaining('Ahmet Yılmaz'), findsNothing);
  });

  testWidgets('375px genislikte tasma/exception olusmaz', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpSection(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('1.6x text scale altinda tasma/exception olusmaz', (
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
          body: SingleChildScrollView(
            child: ProfileAccountPreferencesSection(
              onAddresses: () {},
              onPaymentMethods: () {},
              onNotificationSettings: () {},
              onAccountData: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
