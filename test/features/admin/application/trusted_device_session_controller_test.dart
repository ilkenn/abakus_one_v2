import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/application/use_cases/trusted_device_session_controller.dart';
import 'package:abakus_one_v2/features/admin/data/device_key_store.dart';
import 'package:abakus_one_v2/features/admin/data/device_session_cache.dart';
import 'package:abakus_one_v2/features/admin/data/trusted_device_repository.dart';
import 'package:abakus_one_v2/features/admin/data/trusted_device_session_gateway.dart';
import 'package:abakus_one_v2/features/admin/domain/trusted_device/device_registration_state.dart';
import 'package:abakus_one_v2/features/admin/domain/trusted_device/trusted_device.dart';

import '../test_support/fake_secure_storage_platform.dart';

class _FakeTrustedDeviceSessionGateway implements TrustedDeviceSessionGateway {
  RequestDeviceRegistrationResult? registrationResult;
  TrustedDeviceSessionException? registrationError;
  int requestRegistrationCallCount = 0;

  RequestDeviceChallengeResult? challengeResult;
  int requestChallengeCallCount = 0;
  String? lastChallengePurpose;

  IssueDeviceSessionResult? sessionResult;
  TrustedDeviceSessionException? issueSessionError;
  int issueSessionCallCount = 0;
  String? lastSignature;

  @override
  Future<RequestDeviceRegistrationResult> requestRegistration({
    required String organizationId,
    required String branchId,
    required String platform,
    required String publicKeyPem,
    required List<String> capabilities,
  }) async {
    requestRegistrationCallCount += 1;
    final error = registrationError;
    if (error != null) throw error;
    return registrationResult!;
  }

  @override
  Future<RequestDeviceChallengeResult> requestChallenge({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String purpose,
  }) async {
    requestChallengeCallCount += 1;
    lastChallengePurpose = purpose;
    return challengeResult!;
  }

  @override
  Future<IssueDeviceSessionResult> issueSession({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String challengeId,
    required String signature,
  }) async {
    issueSessionCallCount += 1;
    lastSignature = signature;
    final error = issueSessionError;
    if (error != null) throw error;
    return sessionResult!;
  }
}

class _FakeTrustedDeviceRepository implements TrustedDeviceRepository {
  final _controller = StreamController<List<TrustedDevice>>.broadcast();

  void emit(TrustedDevice device) {
    _controller.add([device]);
  }

  void emitError(Object error) {
    _controller.addError(error);
  }

  void dispose() {
    _controller.close();
  }

  @override
  Stream<List<TrustedDevice>> watchDevicesForBranch({
    required String organizationId,
    required String branchId,
  }) {
    return _controller.stream;
  }
}

TrustedDevice _device({
  required String deviceId,
  required TrustedDeviceStatus status,
}) {
  return TrustedDevice(
    deviceId: deviceId,
    organizationId: 'org-1',
    branchId: 'branch-1',
    platform: TrustedDevicePlatform.android,
    capabilities: const [TrustedDeviceCapability.pos],
    status: status,
    trustTier: TrustedDeviceTrustTier.platformProtected,
    registeredByUid: 'staff-1',
    registeredAt: DateTime(2026, 1, 1),
    version: 1,
  );
}

void main() {
  late FakeSecureStoragePlatform fakeStoragePlatform;
  late _FakeTrustedDeviceSessionGateway gateway;
  late _FakeTrustedDeviceRepository repository;

  setUp(() {
    fakeStoragePlatform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakeStoragePlatform;
    gateway = _FakeTrustedDeviceSessionGateway();
    repository = _FakeTrustedDeviceRepository();
  });

  tearDown(() {
    repository.dispose();
  });

  TrustedDeviceSessionController buildController(
      {bool platformSupported = true}) {
    return TrustedDeviceSessionController(
      keyStore: SecureDeviceKeyStore(
        storage: const FlutterSecureStorage(),
        isPlatformSupported: platformSupported,
      ),
      sessionCache: DeviceSessionCache(storage: const FlutterSecureStorage()),
      sessionGateway: gateway,
      deviceRepository: repository,
      organizationId: 'org-1',
      branchId: 'branch-1',
      environment: 'test',
      devicePlatformWireValue: 'android',
    );
  }

  test(
      'an unsupported platform starts and stays UnsupportedPlatform, never '
      'attempts to generate a key', () async {
    final controller = buildController(platformSupported: false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, isA<UnsupportedPlatform>());

    await controller.register(capabilities: const ['POS']);
    expect(controller.state, isA<UnsupportedPlatform>());
    expect(gateway.requestRegistrationCallCount, 0);
  });

  test('a supported platform with nothing stored starts as NotRegistered',
      () async {
    final controller = buildController();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, isA<NotRegistered>());
  });

  test(
      'register(): generates a key, calls requestRegistration, and moves to '
      'RegistrationRequested while the server status is pending', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'pending',
      alreadyRegistered: false,
      approvalRequestId: 'approval-1',
    );

    await controller.register(capabilities: const ['POS']);

    expect(gateway.requestRegistrationCallCount, 1);
    final state = controller.state;
    expect(state, isA<RegistrationRequested>());
    expect((state as RegistrationRequested).deviceId, 'device-1');
    expect(state.approvalRequestId, 'approval-1');
  });

  test(
      'observing the device transition to active moves '
      'RegistrationRequested -> ActivationRequired', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'pending',
      alreadyRegistered: false,
      approvalRequestId: 'approval-1',
    );
    await controller.register(capabilities: const ['POS']);
    expect(controller.state, isA<RegistrationRequested>());

    repository.emit(
        _device(deviceId: 'device-1', status: TrustedDeviceStatus.active));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, isA<ActivationRequired>());
  });

  test(
      'activateOrRefresh(): challenge -> sign -> issue -> ActiveSession, '
      'and the signature is genuinely produced by the stored key (not a '
      'placeholder)', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'active',
      alreadyRegistered: false,
      approvalRequestId: null,
    );
    await controller.register(capabilities: const ['POS']);
    expect(controller.state, isA<ActivationRequired>());

    gateway.challengeResult = RequestDeviceChallengeResult(
      challengeId: 'challenge-1',
      nonce: 'server-nonce-xyz',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    gateway.sessionResult = IssueDeviceSessionResult(
      sessionId: 'session-1',
      expiresAt: DateTime.now().add(const Duration(hours: 12)),
      deviceId: 'device-1',
    );

    await controller.activateOrRefresh();

    expect(gateway.requestChallengeCallCount, 1);
    expect(gateway.lastChallengePurpose, 'issue');
    expect(gateway.issueSessionCallCount, 1);
    expect(gateway.lastSignature, isNotEmpty);
    final state = controller.state;
    expect(state, isA<ActiveSession>());
    expect((state as ActiveSession).sessionId, 'session-1');
  });

  test(
      'ensureFreshSession(): a session well within its lifetime is '
      'returned as-is, no refresh call made', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'active',
      alreadyRegistered: false,
    );
    await controller.register(capabilities: const ['POS']);
    gateway.challengeResult = RequestDeviceChallengeResult(
      challengeId: 'c1',
      nonce: 'nonce-1',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    gateway.sessionResult = IssueDeviceSessionResult(
      sessionId: 'session-1',
      expiresAt: DateTime.now().add(const Duration(hours: 12)),
      deviceId: 'device-1',
    );
    await controller.activateOrRefresh();

    final result = await controller.ensureFreshSession();
    expect(result.sessionId, 'session-1');
    expect(gateway.issueSessionCallCount, 1,
        reason: 'no additional refresh call');
  });

  test(
      'ensureFreshSession(): a session near expiry triggers a silent '
      'refresh and returns the NEW session', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'active',
      alreadyRegistered: false,
    );
    await controller.register(capabilities: const ['POS']);
    gateway.challengeResult = RequestDeviceChallengeResult(
      challengeId: 'c1',
      nonce: 'nonce-1',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    gateway.sessionResult = IssueDeviceSessionResult(
      sessionId: 'session-1',
      expiresAt: DateTime.now()
          .add(const Duration(minutes: 10)), // within refresh window
      deviceId: 'device-1',
    );
    await controller.activateOrRefresh();
    expect(controller.state, isA<ActiveSession>());

    gateway.challengeResult = RequestDeviceChallengeResult(
      challengeId: 'c2',
      nonce: 'nonce-2',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    gateway.sessionResult = IssueDeviceSessionResult(
      sessionId: 'session-2',
      expiresAt: DateTime.now().add(const Duration(hours: 12)),
      deviceId: 'device-1',
    );

    final result = await controller.ensureFreshSession();
    expect(result.sessionId, 'session-2');
    expect(gateway.issueSessionCallCount, 2);
    expect(gateway.lastChallengePurpose, 'renew');
  });

  test(
      'device suspended -> DeviceSuspended, session cleared from cache is '
      'NOT required (server invalidates it) but local state reflects it '
      'immediately', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'pending',
      alreadyRegistered: false,
      approvalRequestId: 'approval-1',
    );
    await controller.register(capabilities: const ['POS']);

    repository.emit(
        _device(deviceId: 'device-1', status: TrustedDeviceStatus.suspended));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, isA<DeviceSuspended>());
  });

  test(
      'device revoked -> DeviceRevoked, and local key/session material is '
      'deleted (never silently reused for a re-registration)', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'pending',
      alreadyRegistered: false,
      approvalRequestId: 'approval-1',
    );
    await controller.register(capabilities: const ['POS']);
    final keyStore =
        SecureDeviceKeyStore(storage: const FlutterSecureStorage());
    expect(await keyStore.hasKey('test_org-1_branch-1'), true);

    repository.emit(
        _device(deviceId: 'device-1', status: TrustedDeviceStatus.revoked));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, isA<DeviceRevoked>());
    expect(await keyStore.hasKey('test_org-1_branch-1'), false);
  });

  test('device retired -> DeviceRetired, local key deleted', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'pending',
      alreadyRegistered: false,
      approvalRequestId: 'approval-1',
    );
    await controller.register(capabilities: const ['POS']);

    repository.emit(
        _device(deviceId: 'device-1', status: TrustedDeviceStatus.retired));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, isA<DeviceRetired>());
  });

  test(
      'resetAndReregister(): clears everything and returns to '
      'NotRegistered, ready for a genuinely new key', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'pending',
      alreadyRegistered: false,
      approvalRequestId: 'approval-1',
    );
    await controller.register(capabilities: const ['POS']);

    await controller.resetAndReregister();
    expect(controller.state, isA<NotRegistered>());

    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-2',
      status: 'pending',
      alreadyRegistered: false,
      approvalRequestId: 'approval-2',
    );
    await controller.register(capabilities: const ['POS']);
    final state = controller.state as RegistrationRequested;
    expect(state.deviceId, 'device-2',
        reason: 'a genuinely new device identity');
  });

  test(
      'a registration network failure surfaces as DeviceNetworkError, '
      'never crashes or silently retries', () async {
    final controller = buildController();
    gateway.registrationError = const TrustedDeviceSessionException(
      'unavailable',
      'Cihaz oturum sistemi şu anda kullanılamıyor.',
    );

    await controller.register(capabilities: const ['POS']);
    expect(controller.state, isA<DeviceNetworkError>());
  });

  test(
      "activateOrRefresh(): a server 'not-found' (a locally-cached device "
      'id with no matching Firestore doc — e.g. a stale pre-REST-bridge '
      'key) surfaces a clear, actionable Turkish message naming the real '
      "recovery action ('Tekrar Dene' re-registers the same device), "
      'never the raw backend string', () async {
    final controller = buildController();
    gateway.registrationResult = const RequestDeviceRegistrationResult(
      deviceId: 'device-1',
      status: 'active',
      alreadyRegistered: false,
    );
    await controller.register(capabilities: const ['POS']);
    gateway.challengeResult = RequestDeviceChallengeResult(
      challengeId: 'c1',
      nonce: 'nonce-1',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    gateway.issueSessionError = const TrustedDeviceSessionException(
      'not-found',
      'No trusted device registration found.',
    );

    await controller.activateOrRefresh();

    final state = controller.state;
    expect(state, isA<DeviceNetworkError>());
    final message = (state as DeviceNetworkError).message;
    expect(message, isNot(contains('No trusted device registration found')),
        reason: 'never the raw English backend string');
    expect(message, contains('Tekrar Dene'),
        reason: 'must point at the actual recovery action');
  });

  // 2026-11-10 — the server rejected a session the local cache still
  // considered valid (emulator data reset): recover with the same key.
  group('recoverFromRejectedSession', () {
    Future<TrustedDeviceSessionController> activeController() async {
      final controller = buildController();
      gateway.registrationResult = const RequestDeviceRegistrationResult(
        deviceId: 'device-1',
        status: 'active',
        alreadyRegistered: false,
      );
      await controller.register(capabilities: const ['POS']);
      gateway.challengeResult = RequestDeviceChallengeResult(
        challengeId: 'c1',
        nonce: 'nonce-1',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
      gateway.sessionResult = IssueDeviceSessionResult(
        sessionId: 'session-1',
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
        deviceId: 'device-1',
      );
      await controller.activateOrRefresh();
      expect(controller.state, isA<ActiveSession>());
      return controller;
    }

    void nextSession(String sessionId) {
      gateway.challengeResult = RequestDeviceChallengeResult(
        challengeId: 'c-$sessionId',
        nonce: 'nonce-$sessionId',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
      gateway.sessionResult = IssueDeviceSessionResult(
        sessionId: sessionId,
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
        deviceId: 'device-1',
      );
    }

    test(
        'issues a fresh session with the existing key (purpose "issue", no '
        're-registration) and caches it', () async {
      final controller = await activeController();
      nextSession('session-2');

      final recovered =
          await controller.recoverFromRejectedSession('session-1');

      expect(recovered, isTrue);
      final state = controller.state as ActiveSession;
      expect(state.sessionId, 'session-2');
      expect(state.deviceId, 'device-1');
      expect(gateway.lastChallengePurpose, 'issue');
      expect(gateway.issueSessionCallCount, 2);
      expect(gateway.requestRegistrationCallCount, 1,
          reason: 'the device registration itself is never redone');

      // The cache now holds the new session: a restart resumes it.
      final cached = await DeviceSessionCache(
        storage: const FlutterSecureStorage(),
      ).readSession('test_org-1_branch-1');
      expect(cached?.sessionId, 'session-2');
    });

    test('a report for a session that is no longer current is a no-op',
        () async {
      final controller = await activeController();
      nextSession('session-2');

      final recovered =
          await controller.recoverFromRejectedSession('some-older-session');

      expect(recovered, isFalse);
      expect((controller.state as ActiveSession).sessionId, 'session-1');
      expect(gateway.issueSessionCallCount, 1);
    });

    test('two concurrent reports issue exactly one new session', () async {
      final controller = await activeController();
      nextSession('session-2');

      final results = await Future.wait([
        controller.recoverFromRejectedSession('session-1'),
        controller.recoverFromRejectedSession('session-1'),
      ]);

      expect(results.where((r) => r).length, 1);
      expect(gateway.issueSessionCallCount, 2,
          reason: 'one initial activation + one recovery');
      expect((controller.state as ActiveSession).sessionId, 'session-2');
    });

    test('fails closed when the new session cannot be issued', () async {
      final controller = await activeController();
      nextSession('session-2');
      gateway.issueSessionError = const TrustedDeviceSessionException(
        'unavailable',
        'Sunucuya ulaşılamadı.',
      );

      final recovered =
          await controller.recoverFromRejectedSession('session-1');

      expect(recovered, isFalse);
      expect(controller.state, isA<DeviceNetworkError>(),
          reason: 'never keeps using the rejected session');
      final cached = await DeviceSessionCache(
        storage: const FlutterSecureStorage(),
      ).readSession('test_org-1_branch-1');
      expect(cached, isNull, reason: 'the rejected session is not cached');
    });
  });

  group('isRecoverableSessionRejection', () {
    bool check(String code, String message) =>
        TrustedDeviceSessionController.isRecoverableSessionRejection(
          code: code,
          message: message,
        );

    test('matches the three server session rejections, both code spellings',
        () {
      expect(check('permission-denied', 'No such device session.'), isTrue);
      expect(check('permission_denied', 'No such device session.'), isTrue,
          reason: 'Windows REST bridge spelling');
      expect(check('permission-denied', 'Device session has expired.'), isTrue);
      expect(
          check('permission-denied', 'Device session is not active.'), isTrue);
    });

    test('ignores every other error', () {
      expect(
        check('permission-denied',
            'Device session does not match the requested device/branch.'),
        isFalse,
      );
      expect(check('permission-denied', 'Missing permission.'), isFalse);
      expect(check('not-found', 'No such device session.'), isFalse);
      expect(check('unavailable', 'Device session has expired.'), isFalse);
    });
  });
}
