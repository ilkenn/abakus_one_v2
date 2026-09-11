import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/otp_screen.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/menu_screen.dart';
import 'package:abakus_one_v2/features/qr/data/table_guest_session_gateway.dart';
import 'package:abakus_one_v2/features/qr/data/technical_identity_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/active_table_context_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_guest_session_dependencies_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/screens/table_guest_entry_screen.dart';

class _FakeTableGuestSessionGateway implements TableGuestSessionGateway {
  _FakeTableGuestSessionGateway({
    this.previewStatus = 'valid',
    this.tableDisplayName = 'Masa 12',
    this.branchDisplayName = 'Abaküs Ortaköy',
    this.openError,
  });

  String previewStatus;
  String? tableDisplayName;
  String? branchDisplayName;
  Object? openError;
  int resolveCallCount = 0;
  int openCallCount = 0;
  String? lastToken;

  @override
  Future<TableQrPreview> resolveToken(String token) async {
    resolveCallCount++;
    lastToken = token;
    return TableQrPreview(
      status: previewStatus,
      tableDisplayName: previewStatus == 'valid' ? tableDisplayName : null,
      branchDisplayName: previewStatus == 'valid' ? branchDisplayName : null,
    );
  }

  @override
  Future<OpenedTableGuestSession> openSession(String token) async {
    openCallCount++;
    if (openError != null) throw openError!;
    return OpenedTableGuestSession(
      sessionId: 'tgs-1',
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      tableDisplayName: tableDisplayName ?? 'Masa 12',
      branchDisplayName: branchDisplayName ?? 'Abaküs Ortaköy',
      expiresAt: DateTime.now().add(const Duration(hours: 6)),
    );
  }

  @override
  Future<void> createServiceRequest({
    required String guestSessionId,
    required ServiceRequestType type,
  }) async {
    throw UnimplementedError('Not used by TableGuestEntryScreen.');
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
      _FakeTableGuestSessionGateway gateway,
      _FakeTechnicalIdentityProvider identity,
    })> pumpEntryScreen(
  WidgetTester tester, {
  String previewStatus = 'valid',
  String tableDisplayName = 'Masa 12',
  String branchDisplayName = 'Abaküs Ortaköy',
  Object? openError,
  bool firebaseReady = true,
  String? preexistingUid,
}) async {
  final gateway = _FakeTableGuestSessionGateway(
    previewStatus: previewStatus,
    tableDisplayName: tableDisplayName,
    branchDisplayName: branchDisplayName,
    openError: openError,
  );
  final identity = _FakeTechnicalIdentityProvider(preexistingUid);

  final container = ProviderContainer(
    overrides: [
      firebaseReadyProvider.overrideWithValue(firebaseReady),
      tableGuestSessionGatewayProvider.overrideWithValue(gateway),
      technicalIdentityProviderProvider.overrideWithValue(identity),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: TableGuestEntryScreen(token: 'qr-token-abc'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, gateway: gateway, identity: identity);
}

void main() {
  testWidgets(
      'geçerli QR: önizleme (masa + şube adı) gösterilir, giriş/OTP ekranı '
      'ASLA gösterilmez', (tester) async {
    await pumpEntryScreen(tester);

    expect(find.text('Masa 12'), findsOneWidget);
    expect(find.text('Abaküs Ortaköy'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(OtpScreen), findsNothing);
  });

  testWidgets(
      'önizlemedeki masa/şube adı backend\'in resolveTableQrToken '
      'yanıtından gelir — sabit kodlanmamış', (tester) async {
    await pumpEntryScreen(
      tester,
      tableDisplayName: 'Masa 4',
      branchDisplayName: 'Abaküs Beşiktaş',
    );

    expect(find.text('Masa 4'), findsOneWidget);
    expect(find.text('Abaküs Beşiktaş'), findsOneWidget);
    expect(find.text('Masa 12'), findsNothing);
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

  testWidgets('rezerve (reserved) masa: hata mesajı gösterilir, oturum açılmaz',
      (tester) async {
    final result = await pumpEntryScreen(tester, previewStatus: 'reserved');

    expect(find.textContaining('rezerve edilmiştir'), findsOneWidget);
    expect(result.gateway.openCallCount, 0);
  });

  testWidgets(
      'Firebase hazır değilse bağlantı hatası gösterilir, resolve '
      'hiç çağrılmaz', (tester) async {
    final result = await pumpEntryScreen(tester, firebaseReady: false);

    expect(find.textContaining('bağlantı kurulamıyor'), findsOneWidget);
    expect(result.gateway.resolveCallCount, 0);
  });

  testWidgets(
      'Masaya Otur: anonymous technical identity kurulur (ensureSignedIn '
      'tam olarak bir kez çağrılır), activeTableContextProvider set edilir, '
      'MenuScreen açılır — giriş/OTP ekranı hiç gösterilmez', (tester) async {
    final result = await pumpEntryScreen(tester);

    await tester.tap(find.text('Masaya Otur'));
    await tester.pumpAndSettle();

    expect(result.identity.ensureSignedInCallCount, 1);
    expect(result.gateway.openCallCount, 1);
    expect(find.byType(MenuScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(OtpScreen), findsNothing);

    final tableContext = result.container.read(activeTableContextProvider);
    expect(tableContext, isNotNull);
    expect(tableContext!.session.id, 'tgs-1');
    expect(tableContext.tableId, 'table-1');
    expect(tableContext.tableName, 'Masa 12');
    expect(tableContext.branchId, 'branch-1');
    expect(tableContext.branchName, 'Abaküs Ortaköy');
    expect(tableContext.guestSession.authenticatedUserId, isNull);
  });

  testWidgets(
      'zaten gerçek (phone-verified) bir oturum varsa, o oturum ASLA '
      'anonim oturumla ezilmez', (tester) async {
    final result = await pumpEntryScreen(
      tester,
      preexistingUid: 'real-phone-verified-customer-uid',
    );

    await tester.tap(find.text('Masaya Otur'));
    await tester.pumpAndSettle();

    expect(result.identity.ensureSignedInCallCount, 1);
    expect(result.identity.currentUid, 'real-phone-verified-customer-uid');
  });

  testWidgets(
      'openSession sunucu tarafında başarısız olursa (yarış durumu — token '
      'artık geçerli değil), hata gösterilir, MenuScreen açılmaz',
      (tester) async {
    await pumpEntryScreen(
      tester,
      openError: const TableGuestSessionException(
        'failed-precondition',
        'QR code is expired.',
      ),
    );

    await tester.tap(find.text('Masaya Otur'));
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
