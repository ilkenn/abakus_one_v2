import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/otp_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/shopping_channel_provider.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/menu_screen.dart';
import 'package:abakus_one_v2/features/qr/data/technical_identity_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_guest_session_dependencies_provider.dart'
    show technicalIdentityProviderProvider;
import 'package:abakus_one_v2/features/takeaway/data/takeaway_guest_session_gateway.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/providers/takeaway_guest_dependencies_provider.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/screens/takeaway_guest_entry_screen.dart';

class _FakeTakeawayGuestSessionGateway implements TakeawayGuestSessionGateway {
  _FakeTakeawayGuestSessionGateway({
    this.previewStatus = 'valid',
    this.branchDisplayName = 'Abaküs Ortaköy',
    this.openError,
  });

  String previewStatus;
  String? branchDisplayName;
  Object? openError;
  int resolveCallCount = 0;
  int openCallCount = 0;
  String? lastToken;

  @override
  Future<TakeawayQrPreview> resolveToken(String token) async {
    resolveCallCount++;
    lastToken = token;
    return TakeawayQrPreview(
      status: previewStatus,
      branchDisplayName: previewStatus == 'valid' ? branchDisplayName : null,
    );
  }

  @override
  Future<OpenedTakeawayGuestSession> openSession(String token) async {
    openCallCount++;
    if (openError != null) throw openError!;
    return OpenedTakeawayGuestSession(
      sessionId: 'tags-1',
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      branchDisplayName: branchDisplayName ?? 'Abaküs Ortaköy',
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      reused: false,
    );
  }
}

class _FakeTechnicalIdentityProvider implements TechnicalIdentityProvider {
  _FakeTechnicalIdentityProvider([this._current]);

  String? _current;
  int ensureSignedInCallCount = 0;

  @override
  String? get currentUid => _current;

  @override
  Future<String> ensureSignedIn() async {
    ensureSignedInCallCount++;
    _current ??= 'freshly-created-anon-uid';
    return _current!;
  }
}

Future<
    ({
      ProviderContainer container,
      _FakeTakeawayGuestSessionGateway gateway,
      _FakeTechnicalIdentityProvider identity,
    })> pumpEntryScreen(
  WidgetTester tester, {
  String previewStatus = 'valid',
  String branchDisplayName = 'Abaküs Ortaköy',
  Object? openError,
  bool firebaseReady = true,
  String? preexistingUid,
}) async {
  final gateway = _FakeTakeawayGuestSessionGateway(
    previewStatus: previewStatus,
    branchDisplayName: branchDisplayName,
    openError: openError,
  );
  final identity = _FakeTechnicalIdentityProvider(preexistingUid);

  final container = ProviderContainer(
    overrides: [
      firebaseReadyProvider.overrideWithValue(firebaseReady),
      takeawayGuestSessionGatewayProvider.overrideWithValue(gateway),
      technicalIdentityProviderProvider.overrideWithValue(identity),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: TakeawayGuestEntryScreen(token: 'qr-token-abc'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, gateway: gateway, identity: identity);
}

void main() {
  testWidgets(
      'geçerli QR: önizleme (şube adı) gösterilir, giriş/OTP ekranı ASLA '
      'gösterilmez', (tester) async {
    await pumpEntryScreen(tester);

    expect(find.text('Abaküs Ortaköy'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(OtpScreen), findsNothing);
  });

  testWidgets(
      'önizlemedeki şube adı backend\'in resolveTakeawayQrToken yanıtından '
      'gelir — sabit kodlanmamış', (tester) async {
    await pumpEntryScreen(tester, branchDisplayName: 'Abaküs Beşiktaş');

    expect(find.text('Abaküs Beşiktaş'), findsOneWidget);
    expect(find.text('Abaküs Ortaköy'), findsNothing);
  });

  testWidgets('geçersiz (invalid) QR: hata mesajı gösterilir', (tester) async {
    await pumpEntryScreen(tester, previewStatus: 'invalid');

    expect(
      find.textContaining('Bu QR kod şu anda geçerli değil'),
      findsOneWidget,
    );
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('süresi dolmuş (expired) QR: hata mesajı gösterilir',
      (tester) async {
    await pumpEntryScreen(tester, previewStatus: 'expired');

    expect(find.textContaining('süresi dolmuş'), findsOneWidget);
  });

  testWidgets('tanınmayan (notFound) QR: hata mesajı gösterilir',
      (tester) async {
    await pumpEntryScreen(tester, previewStatus: 'notFound');

    expect(find.textContaining('tanınmadı'), findsOneWidget);
  });

  testWidgets(
      'Firebase hazır değilse bağlantı hatası gösterilir, resolve '
      'hiç çağrılmaz', (tester) async {
    final result = await pumpEntryScreen(tester, firebaseReady: false);

    expect(find.textContaining('bağlantı kurulamıyor'), findsOneWidget);
    expect(result.gateway.resolveCallCount, 0);
  });

  testWidgets(
      'Siparişe Başla: anonymous technical identity kurulur (ensureSignedIn '
      'tam olarak bir kez çağrılır), guest context/shopping channel set '
      'edilir, MenuScreen açılır — giriş/OTP ekranı hiç gösterilmez',
      (tester) async {
    final result = await pumpEntryScreen(tester);

    await tester.tap(find.text('Siparişe Başla'));
    await tester.pumpAndSettle();

    expect(result.identity.ensureSignedInCallCount, 1);
    expect(result.gateway.openCallCount, 1);
    expect(find.byType(MenuScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(OtpScreen), findsNothing);

    final guestContext = result.container.read(takeawayGuestContextProvider);
    expect(guestContext, isNotNull);
    expect(guestContext!.sessionId, 'tags-1');
    expect(guestContext.guestAuthUid, 'freshly-created-anon-uid');

    final channelContext = result.container.read(shoppingChannelProvider);
    expect(channelContext.isTakeaway, isTrue);
    expect(channelContext.branchId, 'branch-1');
    expect(channelContext.restaurantId, 'restaurant-1');
    expect(channelContext.branchDisplayName, 'Abaküs Ortaköy');
  });

  testWidgets(
      'zaten gerçek (phone-verified) bir oturum varsa, o oturum ASLA '
      'anonim oturumla ezilmez — aynı uid guest context\'e taşınır',
      (tester) async {
    final result = await pumpEntryScreen(
      tester,
      preexistingUid: 'real-phone-verified-customer-uid',
    );

    await tester.tap(find.text('Siparişe Başla'));
    await tester.pumpAndSettle();

    // ensureSignedIn is still called exactly once (delegation contract),
    // but it never triggers a *new* anonymous sign-in on top of the
    // existing session — TechnicalIdentityProvider's own contract, proven
    // here by the returned uid being the pre-existing one, unchanged.
    expect(result.identity.ensureSignedInCallCount, 1);
    final guestContext = result.container.read(takeawayGuestContextProvider);
    expect(guestContext!.guestAuthUid, 'real-phone-verified-customer-uid');
  });

  testWidgets(
      'openSession sunucu tarafında başarısız olursa (yarış durumu — token '
      'artık geçerli değil), hata gösterilir, MenuScreen açılmaz',
      (tester) async {
    await pumpEntryScreen(
      tester,
      openError: const TakeawayGuestSessionException(
        'failed-precondition',
        'QR code is expired.',
      ),
    );

    await tester.tap(find.text('Siparişe Başla'));
    await tester.pumpAndSettle();

    expect(find.byType(MenuScreen), findsNothing);
    expect(
      find.textContaining('Bu QR kod şu anda kullanılamıyor'),
      findsOneWidget,
    );
  });

  testWidgets('Tekrar Dene, resolve\'u yeniden çağırır', (tester) async {
    final result = await pumpEntryScreen(tester, previewStatus: 'notFound');
    expect(result.gateway.resolveCallCount, 1);

    await tester.tap(find.text('Tekrar Dene'));
    await tester.pumpAndSettle();

    expect(result.gateway.resolveCallCount, 2);
  });
}
