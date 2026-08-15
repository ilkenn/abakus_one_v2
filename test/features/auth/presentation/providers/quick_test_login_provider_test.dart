import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/auth/real_customer_check.dart';
import 'package:abakus_one_v2/core/router/app_route_guard.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/data/emulator_verification_code_client.dart';
import 'package:abakus_one_v2/features/auth/data/quick_test_login_config.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/quick_test_login_provider.dart';

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;
  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> writeSession(AuthSession session) async => stored = session;
  @override
  Future<void> clearSession() async => stored = null;
}

/// Scriptable fake — never touches real HTTP/the real emulator. Records
/// every call so tests can assert exactly what phone number was queried
/// (proving the orchestration reuses the *same* phone number
/// `requestOtp` was called with, not an independently-guessed one).
class _FakeEmulatorVerificationCodeClient
    implements EmulatorVerificationCodeClient {
  _FakeEmulatorVerificationCodeClient({this.codeToReturn, this.errorToThrow});

  final String? codeToReturn;
  final EmulatorVerificationCodeException? errorToThrow;
  final List<String> queriedPhoneNumbers = [];

  @override
  Future<String?> fetchLatestCode({
    required String host,
    required int port,
    required String projectId,
    required String phoneNumber,
  }) async {
    queriedPhoneNumbers.add(phoneNumber);
    if (errorToThrow != null) throw errorToThrow!;
    return codeToReturn;
  }
}

void main() {
  late _FakeSessionStorage sessionStorage;

  ProviderContainer buildContainer({
    String? codeToReturn = DevelopmentLocalAuthRepository.developmentOtpCode,
    EmulatorVerificationCodeException? errorToThrow,
  }) {
    sessionStorage = _FakeSessionStorage();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          DevelopmentLocalAuthRepository(sessionStorage: sessionStorage),
        ),
        emulatorVerificationCodeClientProvider.overrideWithValue(
          _FakeEmulatorVerificationCodeClient(
            codeToReturn: codeToReturn,
            errorToThrow: errorToThrow,
          ),
        ),
      ],
    );
    return container;
  }

  test(
      'uses the existing phone-verification path: requestOtp is called with '
      'the configured dev phone, the fetched code is queried for that exact '
      'phone, and verifyOtp completes sign-in (req 3)', () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    final fakeClient = container.read(emulatorVerificationCodeClientProvider)
        as _FakeEmulatorVerificationCodeClient;

    final success = await container.read(quickTestLoginProvider.notifier).run();

    expect(success, isTrue);
    final authState = container.read(authProvider);
    expect(authState.isAuthenticated, isTrue);
    expect(
      authState.session!.phoneNumber,
      '+90${QuickTestLoginConfig.developmentPhoneLocalInput}',
    );
    expect(fakeClient.queriedPhoneNumbers, [
      '+90${QuickTestLoginConfig.developmentPhoneLocalInput}',
    ]);
  });

  test(
      'the resulting authenticated identity is treated as a real phone '
      'customer, not a guest (req 4)', () async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await container.read(quickTestLoginProvider.notifier).run();

    final authState = container.read(authProvider);
    expect(isRealCustomer(authState), isTrue);
  });

  test(
      'a real-phone-customer session from Quick Test Login satisfies the '
      'reservation route guard exactly like a manual sign-in would (req 7)',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await container.read(quickTestLoginProvider.notifier).run();
    final authState = container.read(authProvider);

    final redirect = AppRouteGuard.resolve(
      location: AppRoutes.reservationPrefix,
      isAuthenticated: authState.isAuthenticated,
      isGuest: authState.isGuest,
      isOnboardingComplete: true,
      isRealCustomer: isRealCustomer(authState),
    );

    expect(redirect, isNull,
        reason: 'null means no redirect — access to /reservation is granted');
  });

  test(
      'a missing emulator verification code fails safely: no session is '
      'created, an error is surfaced, verifyOtp is never satisfied (req 5, 9)',
      () async {
    final container = buildContainer(codeToReturn: null);
    addTearDown(container.dispose);
    // `quickTestLoginProvider` is `.autoDispose` — in the real app,
    // `LoginScreen`'s own `ref.watch` keeps it alive across the run; here a
    // manual listener does the same, otherwise the provider (and its
    // error) is torn down as soon as the last `.read` call's synchronous
    // scope ends.
    container.listen(quickTestLoginProvider, (_, __) {});

    final success = await container.read(quickTestLoginProvider.notifier).run();

    expect(success, isFalse);
    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(
      container.read(quickTestLoginProvider).error,
      contains('bulunamadı'),
    );
  });

  test(
      'an unreachable emulator fails safely: no session is created, no fake '
      'fallback authentication ever occurs (req 5, 9)', () async {
    final container = buildContainer(
      codeToReturn: null,
      errorToThrow:
          const EmulatorVerificationCodeException('connection refused'),
    );
    addTearDown(container.dispose);
    container.listen(quickTestLoginProvider, (_, __) {});

    final success = await container.read(quickTestLoginProvider.notifier).run();

    expect(success, isFalse);
    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(container.read(quickTestLoginProvider).error, isNotNull);
  });

  test(
      'a wrong/malformed code returned by the emulator is rejected by the '
      'real verifyOtp path exactly like a wrong manual entry would (req 5, 9)',
      () async {
    final container = buildContainer(codeToReturn: '000000');
    addTearDown(container.dispose);
    container.listen(quickTestLoginProvider, (_, __) {});

    final success = await container.read(quickTestLoginProvider.notifier).run();

    expect(success, isFalse);
    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(container.read(quickTestLoginProvider).error, isNotNull);
  });
}
