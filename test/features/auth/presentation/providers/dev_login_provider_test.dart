import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/auth/real_customer_check.dart';
import 'package:abakus_one_v2/features/auth/data/dev_login_config.dart';
import 'package:abakus_one_v2/features/auth/data/emulator_verification_code_client.dart';
import 'package:abakus_one_v2/features/auth/data/quick_test_login_config.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/dev_login_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/quick_test_login_provider.dart'
    show emulatorVerificationCodeClientProvider;

/// TEMPORARY_DEVELOPER_LOGIN
///
/// This file's positive-path and negative-comparison tests (everything
/// except the "PIN absent -> fails closed" group) require
/// `DevLoginConfig.pin` — the real `DEV_LOGIN_PIN` compile-time define —
/// to actually be set, because [DevLoginNotifier.run] independently
/// re-checks [DevLoginConfig.isAvailable] before comparing anything, by
/// design ("fail closed" is not optional). Run:
///
///   flutter test --dart-define=DEV_LOGIN_PIN=1234 \
///     test/features/auth/presentation/providers/dev_login_provider_test.dart
///
/// Under the plain `flutter test` default (no `--dart-define`, the CI/
/// whole-suite invocation), `DevLoginConfig.pin` is empty and those tests
/// are explicitly `skip`-ped with a clear reason rather than silently
/// passing on the wrong premise — the ONE test that both proves and
/// requires the absent-PIN case runs unconditionally instead.
/// The exact stale test-fixture phone shape `functions/src/test/*.test.ts`'s
/// `createRealPhoneUser()` helpers use (`+1555${namespace}${counter}`) —
/// named explicitly here only so a regression test can assert it never
/// appears anywhere near the real developer-login path.
const _staleTestFixturePhone = '+1555864447001';

/// The demo project id `firebase emulators:exec`/the backend test suites
/// use — named explicitly so a regression test can assert developer login
/// never queries it.
const _staleTestFixtureProjectId = 'demo-abakus-one-emulator';

/// A fake, but realistic, "current live Firebase app" project id — proves
/// the real value is threaded through end-to-end, not merely "some string."
const _fakeLiveProjectId = 'abakus-one-dev-test-fixture';

void main() {
  late _FakeSessionStorage sessionStorage;
  late _FakeEmulatorVerificationCodeClient fakeClient;
  final pinConfigured = DevLoginConfig.pin.isNotEmpty;
  const wrongPin = 'not-the-real-pin';
  const wrongPhoneInput = '5551234567';
  const correctPhoneInput =
      '5337106414'; // == DevLoginConfig.developerPhoneLocalInput

  ProviderContainer buildContainer({
    String? codeToReturn = DevelopmentLocalAuthRepository.developmentOtpCode,
    String liveProjectId = _fakeLiveProjectId,
  }) {
    sessionStorage = _FakeSessionStorage();
    fakeClient =
        _FakeEmulatorVerificationCodeClient(codeToReturn: codeToReturn);
    return ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          DevelopmentLocalAuthRepository(sessionStorage: sessionStorage),
        ),
        emulatorVerificationCodeClientProvider.overrideWithValue(fakeClient),
        // TEMPORARY_DEVELOPER_LOGIN — mirrors real bootstrap wiring
        // (`main.dart` overriding `firebaseReadyProvider`): a test never
        // has a real Firebase app, so this MUST be overridden explicitly
        // for `DevLoginNotifier.run()` to reach the emulator-code lookup
        // at all — `Firebase.app()` itself would throw otherwise.
        currentFirebaseProjectIdProvider.overrideWithValue(liveProjectId),
      ],
    );
  }

  test(
      'when DEV_LOGIN_PIN is not configured (the plain `flutter test` default), developer login fails closed even with the exact correct phone and a plausible PIN',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    final success = await container.read(devLoginProvider.notifier).run(
          phoneInput: correctPhoneInput,
          pin: '0000',
        );

    expect(success, isFalse);
    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(container.read(devLoginProvider).error,
        'Geliştirici girişi başarısız.');
  },
      skip: pinConfigured
          ? 'covers the absent-PIN case specifically; a real PIN is configured in this run — see the configured-PIN group below instead'
          : false);

  test(
      'correct phone + correct PIN delegates to the real phone-auth emulator flow and results in an authenticated real-phone-customer session',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    final success = await container.read(devLoginProvider.notifier).run(
          phoneInput: correctPhoneInput,
          pin: DevLoginConfig.pin,
        );

    expect(success, isTrue);
    final authState = container.read(authProvider);
    expect(authState.isAuthenticated, isTrue);
    expect(
      authState.session!.phoneNumber,
      '+90${QuickTestLoginConfig.developmentPhoneLocalInput}',
    );
    // The resulting identity is a real phone customer — proven the same
    // way quick_test_login_provider_test.dart already proves it for the
    // underlying flow this delegates to.
    expect(isRealCustomer(authState), isTrue);
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  test(
      'a wrong phone number is rejected with the generic dev-only error — no session created',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    final success = await container.read(devLoginProvider.notifier).run(
          phoneInput: wrongPhoneInput,
          pin: DevLoginConfig.pin,
        );

    expect(success, isFalse);
    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(container.read(devLoginProvider).error,
        'Geliştirici girişi başarısız.');
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  test(
      'a wrong PIN is rejected with the generic dev-only error — no session created',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    final success = await container.read(devLoginProvider.notifier).run(
          phoneInput: correctPhoneInput,
          pin: wrongPin,
        );

    expect(success, isFalse);
    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(container.read(devLoginProvider).error,
        'Geliştirici girişi başarısız.');
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  test(
      'the error text never distinguishes wrong-phone from wrong-PIN — never exposing which part was correct',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    await container
        .read(devLoginProvider.notifier)
        .run(phoneInput: wrongPhoneInput, pin: DevLoginConfig.pin);
    final wrongPhoneError = container.read(devLoginProvider).error;

    final container2 = buildContainer();
    addTearDown(container2.dispose);
    container2.listen(devLoginProvider, (_, __) {});
    await container2
        .read(devLoginProvider.notifier)
        .run(phoneInput: correctPhoneInput, pin: wrongPin);
    final wrongPinError = container2.read(devLoginProvider).error;

    expect(wrongPhoneError, wrongPinError);
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  test(
      'does not delegate the underlying emulator flow\'s own (more specific) error text — surfaces only the locked generic message',
      () async {
    final container = buildContainer(
        codeToReturn:
            null); // would-be-successful phone/PIN, but the emulator has no code
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    final success = await container.read(devLoginProvider.notifier).run(
          phoneInput: correctPhoneInput,
          pin: DevLoginConfig.pin,
        );

    expect(success, isFalse);
    expect(container.read(devLoginProvider).error,
        'Geliştirici girişi başarısız.');
    expect(
        container.read(devLoginProvider).error, isNot(contains('bulunamadı')));
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  // =========================================================================
  // Regression coverage — stale QuickTestLogin substitution bug
  // =========================================================================

  test(
      'the developer-entered +905337106414 is exactly the phone number sent to phone auth — never re-derived independently',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    await container.read(devLoginProvider.notifier).run(
          phoneInput: correctPhoneInput,
          pin: DevLoginConfig.pin,
        );

    expect(container.read(authProvider).session!.phoneNumber, '+905337106414');
    expect(fakeClient.lastQueriedPhoneNumber, '+905337106414');
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  test(
      'the stale QuickTestLogin test-fixture phone (+1555864447001) is never substituted for the developer-entered number',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    await container.read(devLoginProvider.notifier).run(
          phoneInput: correctPhoneInput,
          pin: DevLoginConfig.pin,
        );

    expect(fakeClient.lastQueriedPhoneNumber, isNot(_staleTestFixturePhone));
    expect(container.read(authProvider).session!.phoneNumber,
        isNot(_staleTestFixturePhone));
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  test(
      'the emulator verification-code REST query uses the CURRENT live Firebase app projectId, not a hardcoded one',
      () async {
    const distinctiveProjectId = 'abakus-one-dev-distinctive-marker';
    final container = buildContainer(liveProjectId: distinctiveProjectId);
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    await container.read(devLoginProvider.notifier).run(
          phoneInput: correctPhoneInput,
          pin: DevLoginConfig.pin,
        );

    expect(fakeClient.lastQueriedProjectId, distinctiveProjectId);
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  test(
      'the stale demo-abakus-one-emulator test-fixture project id is never queried by developer login',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    container.listen(devLoginProvider, (_, __) {});

    await container.read(devLoginProvider.notifier).run(
          phoneInput: correctPhoneInput,
          pin: DevLoginConfig.pin,
        );

    expect(fakeClient.lastQueriedProjectId, isNot(_staleTestFixtureProjectId));
    expect(fakeClient.queriedProjectIds,
        isNot(contains(_staleTestFixtureProjectId)));
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  test(
      'a project-id mismatch cannot occur — the SAME projectId this provider resolves is what the verification-code query receives, for two different live-project fixtures',
      () async {
    for (final projectId in [
      'abakus-one-dev-fixture-a',
      'abakus-one-dev-fixture-b'
    ]) {
      final container = buildContainer(liveProjectId: projectId);
      addTearDown(container.dispose);
      container.listen(devLoginProvider, (_, __) {});

      await container.read(devLoginProvider.notifier).run(
            phoneInput: correctPhoneInput,
            pin: DevLoginConfig.pin,
          );

      expect(fakeClient.lastQueriedProjectId, projectId);
    }
  },
      skip: pinConfigured
          ? false
          : 'requires --dart-define=DEV_LOGIN_PIN=<value>');

  test(
      'dev_login_provider.dart never hardcodes the stale test-fixture phone or project id in its own source',
      () {
    // Structural regression guard, mirrors
    // emulator_verification_code_client_test.dart's own "no dart:io
    // import" source-text check — catches a reintroduced hardcoded value
    // even if every other test above happened to still pass by
    // coincidence.
    final source = File(
      'lib/features/auth/presentation/providers/dev_login_provider.dart',
    ).readAsStringSync();
    expect(source.contains(_staleTestFixturePhone), isFalse);
    expect(source.contains(_staleTestFixtureProjectId), isFalse);
  });
}

class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;
  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> writeSession(AuthSession session) async => stored = session;
  @override
  Future<void> clearSession() async => stored = null;
}

class _FakeEmulatorVerificationCodeClient
    implements EmulatorVerificationCodeClient {
  _FakeEmulatorVerificationCodeClient({this.codeToReturn});
  final String? codeToReturn;

  String? lastQueriedProjectId;
  String? lastQueriedPhoneNumber;
  final List<String> queriedProjectIds = [];
  final List<String> queriedPhoneNumbers = [];

  @override
  Future<String?> fetchLatestCode({
    required String host,
    required int port,
    required String projectId,
    required String phoneNumber,
  }) async {
    lastQueriedProjectId = projectId;
    lastQueriedPhoneNumber = phoneNumber;
    queriedProjectIds.add(projectId);
    queriedPhoneNumbers.add(phoneNumber);
    return codeToReturn;
  }
}
