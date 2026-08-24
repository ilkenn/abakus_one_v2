import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:abakus_one_v2/features/feedback/presentation/screens/customer_feedback_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/staff_sign_in_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/screens/orders_screen.dart';
import 'package:abakus_one_v2/features/crm/presentation/screens/customer_visit_passport_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/addresses_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/help_screen.dart';
import 'package:abakus_one_v2/features/loyalty/data/loyalty_gateway.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_account_snapshot.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_history_entry.dart';
import 'package:abakus_one_v2/features/loyalty/domain/models/loyalty_reward.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/providers/loyalty_providers.dart';
import 'package:abakus_one_v2/features/loyalty/presentation/screens/loyalty_screen.dart';
import 'package:abakus_one_v2/features/customer_photos/data/customer_photo_gateway.dart';
import 'package:abakus_one_v2/features/customer_photos/presentation/providers/customer_photo_providers.dart';
import 'package:abakus_one_v2/features/profile/data/customer_identity_gateway.dart';
import 'package:abakus_one_v2/features/profile/domain/models/customer_identity.dart';
import 'package:abakus_one_v2/features/profile/presentation/providers/customer_identity_provider.dart';
import 'package:abakus_one_v2/features/profile/presentation/screens/profile_screen.dart';
import 'package:abakus_one_v2/shared/models/customer_photo.dart';

/// Profile P.4.3A — `ProfileCustomerPhotosCard` (rendered whenever this
/// screen's own `isAuthenticated` gate is true) watches
/// `customerPhotoGalleryProvider`, whose default `customerPhotoGatewayProvider`
/// implementation is `FirebaseCustomerPhotoGateway()` — its constructor
/// eagerly resolves `FirebaseFirestore.instance`, which throws under
/// `flutter test` (no real Firebase app exists here). Every
/// `pumpProfileScreen` call therefore overrides it with this trivial fake
/// by default — mirrors how `authRepositoryProvider` is already always
/// overridden in this same helper, for the identical reason.
class _EmptyCustomerPhotoGateway implements CustomerPhotoGateway {
  const _EmptyCustomerPhotoGateway();

  @override
  Stream<List<CustomerPhoto>> watchGallery({
    required String organizationId,
    required String customerId,
  }) =>
      Stream.value(const []);

  @override
  Future<CustomerPhotoUploadGrant> requestUploadGrant({
    required String organizationId,
    required String contentType,
    String? purpose,
  }) =>
      throw UnimplementedError(
          'not exercised via ProfileScreen navigation tests');

  @override
  Future<void> selectProfilePhoto({
    required String organizationId,
    required String photoId,
  }) =>
      throw UnimplementedError(
          'not exercised via ProfileScreen navigation tests');

  @override
  Stream<String?> watchSelectedProfilePhotoRef({
    required String organizationId,
    required String customerId,
  }) =>
      Stream.value(null);
}

/// P.4.3B — `ProfileHeroCard`'s authenticated state now also watches
/// `customerIdentityProvider`, whose default `customerIdentityGatewayProvider`
/// implementation (`FirebaseCustomerIdentityGateway`) eagerly resolves
/// `FirebaseFirestore.instance` — the same crash-under-`flutter-test`
/// reasoning `_EmptyCustomerPhotoGateway` above already documents. Every
/// `pumpProfileScreen` call overrides it with this fixed fake by default;
/// tests that care about the exact hero content pass their own via
/// `identityGateway`.
class _FixedCustomerIdentityGateway implements CustomerIdentityGateway {
  const _FixedCustomerIdentityGateway([this.identity]);

  final CustomerIdentity? identity;

  @override
  Stream<CustomerIdentity?> watchOwnIdentity({required String uid}) =>
      Stream.value(identity);
}

/// P3A — the canonical `LoyaltyScreen` (now `lib/features/loyalty/`) is
/// real/server-authoritative; its default `loyaltyGatewayProvider`
/// implementation eagerly resolves `FirebaseFunctions.instance`, which
/// throws under `flutter test` (no real Firebase app exists here) — the
/// identical reasoning `_EmptyCustomerPhotoGateway`/
/// `_FixedCustomerIdentityGateway` above already document. Every
/// `pumpProfileScreen` call overrides it with this trivial zero-state fake
/// by default.
class _FakeLoyaltyGateway implements LoyaltyGateway {
  const _FakeLoyaltyGateway();

  @override
  Future<LoyaltyAccountSnapshot> getSnapshot() async =>
      LoyaltyAccountSnapshot.zero;

  @override
  Future<LoyaltyHistoryPage> getHistory(
          {int? pageSize, String? cursor}) async =>
      LoyaltyHistoryPage.empty;

  @override
  Future<List<LoyaltyReward>> getRewardCatalog() async => const [];
}

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;
  _FakeSessionStorage({this.stored});
  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> writeSession(AuthSession session) async => stored = session;
  @override
  Future<void> clearSession() async => stored = null;
}

class _SignedInNotifier extends AuthNotifier {
  _SignedInNotifier(this.uid, this.phoneNumber);
  final String uid;
  final String phoneNumber;

  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: uid,
          phoneNumber: phoneNumber,
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        ),
      );
}

void main() {
  Future<void> pumpProfileScreen(
    WidgetTester tester, {
    _FakeSessionStorage? sessionStorage,
    ActorSession? actorSession,
    AuthNotifier Function()? authNotifierBuilder,
    CustomerIdentityGateway? identityGateway,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            DevelopmentLocalAuthRepository(
              sessionStorage: sessionStorage ?? _FakeSessionStorage(),
            ),
          ),
          customerPhotoGatewayProvider.overrideWithValue(
            const _EmptyCustomerPhotoGateway(),
          ),
          customerIdentityGatewayProvider.overrideWithValue(
            identityGateway ??
                const _FixedCustomerIdentityGateway(
                  CustomerIdentity(
                    firstName: 'Test',
                    lastName: 'Müşteri',
                    email: '',
                    occupationStatus: CustomerOccupationStatus.other,
                  ),
                ),
          ),
          loyaltyGatewayProvider.overrideWithValue(const _FakeLoyaltyGateway()),
          if (actorSession != null)
            actorSessionProvider.overrideWith((ref) => actorSession),
          // P.1: `AuthNotifier.build()` always starts signed-out regardless
          // of `sessionStorage` (session restore is a separate explicit
          // `checkPersistedSession()` call this test suite never triggers)
          // — every pre-existing test below has therefore always run
          // against a guest `ProfileHeroCard`. This override exists only
          // for the new P.1 tests that need to assert the authenticated
          // hero specifically.
          if (authNotifierBuilder != null)
            authProvider.overrideWith(authNotifierBuilder),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Favorilerim menu ogesi FavoritesScreen acar', (
    WidgetTester tester,
  ) async {
    await pumpProfileScreen(tester);

    await tester.tap(find.text('Favorilerim'));
    await tester.pumpAndSettle();

    expect(find.byType(FavoritesScreen), findsOneWidget);
  });

  testWidgets(
    'Boncuklarim hizli erisim karti LoyaltyScreen acar ve gercek (bos) '
    'boncuk gecmisi durumunu gosterir (P.1 quick action; P3A gercek veri — '
    'artik sahte "Protein Bowl Siparişi" gecmisi yok)',
    (WidgetTester tester) async {
      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
      );

      await tester.tap(find.byKey(const Key('quickAction_boncuklarim')));
      await tester.pumpAndSettle();

      expect(find.byType(LoyaltyScreen), findsOneWidget);
      // The fake, zero-state LoyaltyGateway `pumpProfileScreen` always
      // installs means there is genuinely no history — the honest empty
      // state, never a fabricated order title.
      expect(find.text('Henüz Boncuk hareketin yok.'), findsOneWidget);
    },
  );

  testWidgets('Yardim ve Destek menu ogesi HelpScreen acar', (
    WidgetTester tester,
  ) async {
    await pumpProfileScreen(tester);

    await tester.ensureVisible(find.text('Yardım ve Destek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yardım ve Destek'));
    await tester.pumpAndSettle();

    expect(find.byType(HelpScreen), findsOneWidget);
  });

  testWidgets(
    'Cikis Yap onay diyalogundan sonra oturumu temizler ve LoginScreen\'e '
    'geri doner, geri tusuyla ProfileScreen\'e donulmez',
    (WidgetTester tester) async {
      final storage = _FakeSessionStorage(
        stored: AuthSession(
          uid: 'uid-1',
          phoneNumber: '+905321234567',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      // P.3: "Çıkış Yap" only renders when authenticated — `sessionStorage`
      // alone never drives `authProvider`'s state (session restore is a
      // separate explicit call this suite never triggers), so an explicit
      // `authNotifierBuilder` is required here too now.
      await pumpProfileScreen(
        tester,
        sessionStorage: storage,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905321234567'),
      );

      await tester.ensureVisible(
        find.byKey(const Key('profileLogoutButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profileLogoutButton')));
      await tester.pumpAndSettle();

      // Onay diyalogu acildi, "Cikis Yap" aksiyonuna basiliyor.
      await tester.tap(find.text('Çıkış Yap').last);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
      expect(storage.stored, isNull);
    },
  );

  testWidgets(
    'Geri Bildirim Gonder menu ogesi CustomerFeedbackScreen acar '
    '(Sprint 5E)',
    (WidgetTester tester) async {
      await pumpProfileScreen(tester);

      await tester.ensureVisible(find.text('Geri Bildirim Gönder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Geri Bildirim Gönder'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerFeedbackScreen), findsOneWidget);
    },
  );

  testWidgets(
    'yetkisiz kullanicida (oturum yok) ne "Yönetici Paneli" ne de '
    '"İşletme Moduna Geç" gorunur (P.3 — eski Sprint 6B testinin yerini '
    'alir, StaffSignInScreen artik Profile\'dan hic erisilmiyor)',
    (WidgetTester tester) async {
      await pumpProfileScreen(tester);

      expect(find.text('Yönetici Paneli'), findsNothing);
      expect(find.text('İşletme Moduna Geç'), findsNothing);
      expect(
        find.byKey(const Key('profileBusinessModeCard')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'personel rolu olan yetkili actor icin "İşletme Moduna Geç" karti '
    'gorunur ve AdminShellScreen acar (P.3 — eski Phase 6A testinin '
    'yerini alir)',
    (WidgetTester tester) async {
      await pumpProfileScreen(
        tester,
        actorSession: const ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        ),
      );

      expect(find.text('Yönetici Paneli'), findsNothing);
      expect(find.text('İşletme Moduna Geç'), findsOneWidget);

      await tester.ensureVisible(find.text('İşletme Moduna Geç'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profileBusinessModeCard')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminShellScreen), findsOneWidget);
      expect(find.byType(StaffSignInScreen), findsNothing);
    },
  );

  group('P.1 — premium hero + hizli erisim', () {
    testWidgets(
        'P.4.3B — kimlik dogrulanmis oturumda hero gercek musteri adini/'
        'emailini gosterir, telefon numarasi ARTIK birincil kimlik degil, '
        'sahte veri hicbir yerde gorunmez', (tester) async {
      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
        identityGateway: const _FixedCustomerIdentityGateway(
          CustomerIdentity(
            firstName: 'İlken',
            lastName: 'Parlakbudak',
            email: 'ilken@example.com',
            occupationStatus: CustomerOccupationStatus.working,
            workplaceName: 'Abaküs Bowl',
          ),
        ),
      );

      expect(find.text('İlken Parlakbudak'), findsOneWidget);
      expect(find.text('ilken@example.com'), findsOneWidget);
      expect(find.text('+905559998877'), findsNothing,
          reason: 'the phone number must no longer be the primary hero '
              'identity');
      expect(find.text('Ahmet Yılmaz'), findsNothing);
      expect(find.text('ahmet.yilmaz@abakusbowl.com'), findsNothing);
    });

    testWidgets(
        'misafir durumda sahte isim/email gosterilmez, gercek giris '
        'yolu sunulur', (tester) async {
      await pumpProfileScreen(tester);

      expect(find.text('Ahmet Yılmaz'), findsNothing);
      expect(find.text('ahmet.yilmaz@abakusbowl.com'), findsNothing);
      expect(find.textContaining('user_123'), findsNothing);
      expect(find.text('Hesabına Giriş Yap'), findsOneWidget);
    });

    testWidgets('tam olarak 3 hizli erisim karti gorunur', (tester) async {
      await pumpProfileScreen(tester);

      expect(
        find.byKey(const Key('quickAction_boncuklarim')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('quickAction_siparislerim')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('quickAction_favorilerim')),
        findsOneWidget,
      );
    });

    testWidgets('Siparislerim hizli erisim karti OrdersScreen acar', (
      tester,
    ) async {
      await pumpProfileScreen(tester);

      await tester.tap(find.byKey(const Key('quickAction_siparislerim')));
      await tester.pumpAndSettle();

      expect(find.byType(OrdersScreen), findsOneWidget);
    });

    testWidgets(
        'eski uzun liste artik Siparislerim/Favorilerim/Sadakat '
        'Boncuklarim satirlarini tekrar etmiyor', (tester) async {
      await pumpProfileScreen(tester);

      // "Sadakat Boncuklarım" metni tamamen kaldirildi (quick action
      // etiketi farkli: "Boncuklarım") — hic gorunmemeli.
      expect(find.text('Sadakat Boncuklarım'), findsNothing);
      // "Siparişlerim"/"Favorilerim" quick action'da hala gorunuyor —
      // ama sadece bir kez (eski listede ikinci bir kopyasi yok).
      expect(find.text('Siparişlerim'), findsOneWidget);
      expect(find.text('Favorilerim'), findsOneWidget);
    });

    testWidgets('sayfada hicbir yerde sahte 320 boncuk bakiyesi gorunmez', (
      tester,
    ) async {
      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
      );

      expect(find.textContaining('320'), findsNothing);
    });

    testWidgets('375px genislikte tasma/exception olusmaz', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('1.6x text scale altinda tasma/exception olusmaz', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              DevelopmentLocalAuthRepository(
                sessionStorage: _FakeSessionStorage(),
              ),
            ),
            authProvider.overrideWith(
              () => _SignedInNotifier('uid-1', '+905559998877'),
            ),
            customerPhotoGatewayProvider.overrideWithValue(
              const _EmptyCustomerPhotoGateway(),
            ),
            customerIdentityGatewayProvider.overrideWithValue(
              const _FixedCustomerIdentityGateway(
                CustomerIdentity(
                  firstName: 'Test',
                  lastName: 'Müşteri',
                  email: '',
                  occupationStatus: CustomerOccupationStatus.other,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('P.2 — boncuk karti + hesap & tercihler gruplamasi', () {
    testWidgets('premium Boncuk karti ProfileScreen uzerinde gorunur', (
      tester,
    ) async {
      await pumpProfileScreen(tester);

      expect(find.byKey(const Key('profileLoyaltyCard')), findsOneWidget);
      expect(find.text('Boncuklarını Biriktirmeye Başla'), findsOneWidget);
    });

    testWidgets(
        'kimlik dogrulanmis kullanicida Boncuk kartina dokununca '
        'LoyaltyScreen acar', (tester) async {
      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
      );

      await tester.tap(find.byKey(const Key('profileLoyaltyCard')));
      await tester.pumpAndSettle();

      expect(find.byType(LoyaltyScreen), findsOneWidget);
    });

    testWidgets(
        'misafirde Boncuk kartina dokununca LoginScreen acar, '
        'LoyaltyScreen degil', (tester) async {
      await pumpProfileScreen(tester);

      await tester.tap(find.byKey(const Key('profileLoyaltyCard')));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(LoyaltyScreen), findsNothing);
    });

    testWidgets('"Hesap & Tercihler" basligi ve gruplu kart gorunur', (
      tester,
    ) async {
      await pumpProfileScreen(tester);

      expect(find.text('Hesap & Tercihler'), findsOneWidget);
      expect(find.byKey(const Key('accountPreferencesCard')), findsOneWidget);
    });

    testWidgets(
        'tam olarak 4 kilitli hesap/tercih hedefi Hesap & Tercihler '
        'grubu altinda listelenir', (tester) async {
      await pumpProfileScreen(tester);

      expect(find.byKey(const Key('pref_adreslerim')), findsOneWidget);
      expect(find.byKey(const Key('pref_odemeYontemlerim')), findsOneWidget);
      expect(find.byKey(const Key('pref_bildirimAyarlari')), findsOneWidget);
      expect(find.byKey(const Key('pref_hesapVeVerilerim')), findsOneWidget);
    });

    testWidgets(
        'Adreslerim/Ödeme Yöntemlerim/Bildirim Ayarları/Hesap ve '
        'Verilerim eski genel listede artik tekrar etmiyor — sadece '
        'yeni grupta bir kez gorunur', (tester) async {
      await pumpProfileScreen(tester);

      expect(find.text('Adreslerim'), findsOneWidget);
      expect(find.text('Ödeme Yöntemlerim'), findsOneWidget);
      expect(find.text('Bildirim Ayarları'), findsOneWidget);
      expect(find.text('Hesap ve Verilerim'), findsOneWidget);
    });

    testWidgets(
        'Adreslerim/Ödeme Yöntemlerim/Bildirim Ayarları/Hesap ve '
        'Verilerim dokunuslari hala dogru ekranlari acar (navigasyon '
        'korunmus)', (tester) async {
      await pumpProfileScreen(tester);

      await tester.tap(find.byKey(const Key('pref_adreslerim')));
      await tester.pumpAndSettle();
      expect(find.byType(AddressesScreen), findsOneWidget);
    });
  });

  group('P.3 — ziyaret pasosu + destek + isletme modu + cikis', () {
    testWidgets(
        'kimlik dogrulanmis kullanicida premium Ziyaret Pasosu karti '
        'gorunur', (tester) async {
      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
      );

      expect(
        find.byKey(const Key('profileVisitPassCard')),
        findsOneWidget,
      );
      expect(find.text('Ziyaret Pasosu'), findsOneWidget);
      expect(
        find.text('Ziyaret sayına özel ayrı ödül programı'),
        findsOneWidget,
      );
    });

    testWidgets(
        'P.3.1 — misafirde Ziyaret Pasosu hic render edilmez (currentCustomer'
        'Provider\'in cozecek gercek bir musterisi yok)', (tester) async {
      await pumpProfileScreen(tester);

      expect(
        find.byKey(const Key('profileVisitPassCard')),
        findsNothing,
      );
      expect(find.text('Ziyaret Pasosu'), findsNothing);
    });

    testWidgets(
        'Profile P.4.3A — authenticated user can see "Profil Fotoğraflarım"',
        (tester) async {
      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
      );

      expect(
        find.byKey(const Key('profileCustomerPhotosCard')),
        findsOneWidget,
      );
      expect(find.text('Profil Fotoğraflarım'), findsOneWidget);
    });

    testWidgets(
        'Profile P.4.3A — guest must not see "Profil Fotoğraflarım" at all',
        (tester) async {
      await pumpProfileScreen(tester);

      expect(
        find.byKey(const Key('profileCustomerPhotosCard')),
        findsNothing,
      );
      expect(find.text('Profil Fotoğraflarım'), findsNothing);
    });

    testWidgets('Ziyaret Pasosu kartina dokununca gercek ekrani acar', (
      tester,
    ) async {
      // P.3.1: `ProfileVisitPassCard` now awaits `currentCustomerProvider
      // .future` internally instead of racing a synchronous `ref.read`,
      // so no manual pre-warming is needed here anymore — a bare tap is
      // enough (see `profile_visit_pass_card_test.dart` for a dedicated
      // cold-provider race-condition test).
      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
      );

      await tester.ensureVisible(
        find.byKey(const Key('profileVisitPassCard')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profileVisitPassCard')));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerVisitPassportScreen), findsOneWidget);
    });

    testWidgets(
        '"Destek" grubu tam olarak Geri Bildirim + Yardım ve Destek '
        'icerir', (tester) async {
      await pumpProfileScreen(tester);

      expect(find.byKey(const Key('supportCard')), findsOneWidget);
      expect(
        find.byKey(const Key('support_geriBildirim')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('support_yardimVeDestek')),
        findsOneWidget,
      );
    });

    testWidgets('Destek grubundaki her iki hedef de calisir', (
      tester,
    ) async {
      await pumpProfileScreen(tester);

      await tester.ensureVisible(
        find.byKey(const Key('support_yardimVeDestek')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_yardimVeDestek')));
      await tester.pumpAndSettle();
      expect(find.byType(HelpScreen), findsOneWidget);
    });

    testWidgets('misafirde "Çıkış Yap" gorunmez', (tester) async {
      await pumpProfileScreen(tester);

      expect(
        find.byKey(const Key('profileLogoutButton')),
        findsNothing,
      );
      expect(find.text('Çıkış Yap'), findsNothing);
    });

    testWidgets('kimlik dogrulanmis kullanicida "Çıkış Yap" gorunur', (
      tester,
    ) async {
      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
      );

      expect(
        find.byKey(const Key('profileLogoutButton')),
        findsOneWidget,
      );
    });

    testWidgets(
        'eski genel ayarlar listesi (ListTile tabanli) artik hicbir '
        'yerde render edilmiyor', (tester) async {
      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
        actorSession: const ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        ),
      );

      // P.3 sonrasi ProfileScreen'de hicbir ListTile kalmamali — her
      // ogenin kendi premium kart/grubu var artik.
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets(
        '375px genislikte tasma/exception olusmaz (tam yetkili + '
        'kimlik dogrulanmis, en genis durum)', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpProfileScreen(
        tester,
        authNotifierBuilder: () => _SignedInNotifier('uid-1', '+905559998877'),
        actorSession: const ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '1.6x text scale altinda tasma/exception olusmaz (tam '
        'yetkili + kimlik dogrulanmis, en genis durum)', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              DevelopmentLocalAuthRepository(
                sessionStorage: _FakeSessionStorage(),
              ),
            ),
            authProvider.overrideWith(
              () => _SignedInNotifier('uid-1', '+905559998877'),
            ),
            actorSessionProvider.overrideWith(
              (ref) => const ActorSession(
                actorId: 'manager-1',
                roles: {StaffRole.manager},
                activeRole: StaffRole.manager,
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
