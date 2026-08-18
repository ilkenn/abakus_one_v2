import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/crm/presentation/providers/current_customer_provider.dart';
import 'package:abakus_one_v2/features/crm/presentation/screens/customer_visit_passport_screen.dart';
import 'package:abakus_one_v2/features/profile/presentation/widgets/profile_visit_pass_card.dart';

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;
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
  testWidgets('premium kart dogru baslik/aciklamayla gorunur, sayi yoktur', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            DevelopmentLocalAuthRepository(
              sessionStorage: _FakeSessionStorage(),
            ),
          ),
          authProvider.overrideWith(
            () => _SignedInNotifier('uid-1', '+905551112233'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ProfileVisitPassCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profileVisitPassCard')), findsOneWidget);
    expect(find.text('Ziyaret Pasosu'), findsOneWidget);
    expect(
      find.text('Ziyaret sayına özel ayrı ödül programı'),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
  });

  testWidgets('dokununca gercek CustomerVisitPassportScreen acar', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          DevelopmentLocalAuthRepository(
            sessionStorage: _FakeSessionStorage(),
          ),
        ),
        authProvider.overrideWith(
          () => _SignedInNotifier('uid-1', '+905551112233'),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Ayni P.3 screen-test'teki gerekce: `currentCustomerProvider` hicbir
    // yerde onceden watch edilmiyor, ilk erisim `ref.read` ile onTap
    // icinde oluyor — container uzerinden once cozerek yaris durumunu
    // onluyoruz.
    await container.read(currentCustomerProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ProfileVisitPassCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileVisitPassCard')));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerVisitPassportScreen), findsOneWidget);
  });

  testWidgets(
      'P.3.1 — provider hicbir yerde onceden cozulmemisken ilk dokunus '
      'yine de cozuldukten sonra hedefe ulasir (yaris durumu duzeltmesi)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            DevelopmentLocalAuthRepository(
              sessionStorage: _FakeSessionStorage(),
            ),
          ),
          authProvider.overrideWith(
            () => _SignedInNotifier('uid-1', '+905551112233'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ProfileVisitPassCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Kasitli olarak `currentCustomerProvider`'i onceden hic okumadan/
    // cozmeden dogrudan dokunuyoruz — eski senkron `ref.read(...)
    // .valueOrNull` burada sessizce hicbir sey yapmazdi (AsyncLoading).
    await tester.tap(find.byKey(const Key('profileVisitPassCard')));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerVisitPassportScreen), findsOneWidget);
  });

  testWidgets(
      'P.3.1 — musteri cozulemezse acik, sahte-olmayan bir mesaj '
      'gosterilir; sessizce hicbir sey yapilmaz', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            DevelopmentLocalAuthRepository(
              sessionStorage: _FakeSessionStorage(),
            ),
          ),
          authProvider.overrideWith(
            () => _SignedInNotifier('uid-1', '+905551112233'),
          ),
          // Cozumleme basarisiz/null donen senaryoyu simule ediyoruz.
          currentCustomerProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ProfileVisitPassCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileVisitPassCard')));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerVisitPassportScreen), findsNothing);
    expect(
      find.text(
        'Ziyaret pasosuna şu anda ulaşılamıyor. Lütfen tekrar dene.',
      ),
      findsOneWidget,
    );
  });
}
