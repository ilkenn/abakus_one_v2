import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/device_key_store.dart';
import '../../data/device_session_cache.dart';
import '../../data/trusted_device_repository.dart';
import '../../data/trusted_device_session_gateway.dart';
import '../../domain/trusted_device/device_registration_state.dart';
import '../../domain/trusted_device/trusted_device.dart';

/// Orchestrates the full trusted-device POS flow — AP-3 continuation
/// (`docs/decisions.md` ADR-041): platform check → key load/create →
/// register → observe manager approval (via the EXISTING staff-facing
/// [TrustedDeviceRepository] stream — this never re-implements approval,
/// it only watches for the outcome) → challenge → sign → issue session →
/// refresh before expiry → fail closed on suspended/revoked/retired/
/// corrupted/network conditions.
///
/// A [StateNotifier] rather than an [AsyncNotifier]: the state machine
/// itself ([DeviceRegistrationState]) already models every failure/loading
/// condition explicitly (this is exactly the "state classes represent
/// explicit states, not booleans layered on top of each other" rule,
/// `CLAUDE.md` §4) — a wrapping `AsyncValue` would only add a second,
/// redundant loading/error dimension on top of states that already carry
/// that meaning themselves.
class TrustedDeviceSessionController
    extends StateNotifier<DeviceRegistrationState> {
  TrustedDeviceSessionController({
    required this.keyStore,
    required this.sessionCache,
    required this.sessionGateway,
    required this.deviceRepository,
    required this.organizationId,
    required this.branchId,
    required this.environment,
    required this.devicePlatformWireValue,
  }) : super(
          keyStore.isPlatformSupported
              ? const NotRegistered()
              : const UnsupportedPlatform(),
        ) {
    _bootstrap();
  }

  final DeviceKeyStore keyStore;
  final DeviceSessionCache sessionCache;
  final TrustedDeviceSessionGateway sessionGateway;
  final TrustedDeviceRepository deviceRepository;
  final String organizationId;
  final String branchId;

  /// Namespaces every stored key/session by build environment as well as
  /// org/branch — never a bare, environment-agnostic key name, which would
  /// risk a dev/staging/production key collision on a shared device.
  final String environment;

  /// Mirrors the server's own `VALID_PLATFORMS`/`PLATFORM_PROTECTED_ELIGIBLE`
  /// wire vocabulary (`trustedDevice.ts`) exactly — resolved once by the
  /// provider construction site (`trusted_device_providers.dart`, via
  /// `defaultTargetPlatform`/`kIsWeb`) and passed in here, rather than this
  /// class re-deriving it itself, so a test can supply any platform value
  /// without needing platform-detection test doubles.
  final String devicePlatformWireValue;

  /// The session is proactively refreshed once fewer than this remains
  /// before expiry — well inside the server's 12-hour session lifetime
  /// (`SESSION_DURATION_SECONDS`, `trustedDevice.ts`), so a refresh has
  /// many retries' worth of margin before an operator would ever see an
  /// unexpected expiry mid-shift.
  static const _refreshLeadTime = Duration(minutes: 30);

  StreamSubscription<List<TrustedDevice>>? _deviceStreamSub;
  String get _namespace => '${environment}_${organizationId}_$branchId';

  Future<void> _bootstrap() async {
    if (!keyStore.isPlatformSupported) {
      state = const UnsupportedPlatform();
      return;
    }
    try {
      final deviceId = await sessionCache.readDeviceId(_namespace);
      if (deviceId == null) {
        state = const NotRegistered();
        return;
      }
      _watchDeviceStatus(deviceId);

      final cachedSession = await sessionCache.readSession(_namespace);
      if (cachedSession != null &&
          cachedSession.expiresAt.isAfter(DateTime.now())) {
        state = ActiveSession(
          deviceId: deviceId,
          sessionId: cachedSession.sessionId,
          expiresAt: cachedSession.expiresAt,
        );
      } else {
        state = ActivationRequired(deviceId);
      }
    } on DeviceKeyStorageCorruptedException catch (e) {
      state = KeyStorageCorrupted(e.toString());
    }
  }

  void _watchDeviceStatus(String deviceId) {
    _deviceStreamSub?.cancel();
    _deviceStreamSub = deviceRepository
        .watchDevicesForBranch(
            organizationId: organizationId, branchId: branchId)
        .listen(
      (devices) {
        final match = devices.where((d) => d.deviceId == deviceId).toList();
        if (match.isEmpty) return;
        _onDeviceStatusObserved(deviceId, match.first.status);
      },
      onError: (_) {
        // A stream error here means the STAFF-facing read failed (e.g.
        // backend unavailable) — never overwrites a genuinely active
        // session with a network-error state; only surfaces it while
        // still waiting on registration/approval, where there is nothing
        // else to fall back to.
        if (state is RegistrationRequested || state is NotRegistered) {
          state = const DeviceNetworkError(
            'Cihaz onay durumu okunamadı. Bağlantınızı kontrol edin.',
          );
        }
      },
    );
  }

  void _onDeviceStatusObserved(String deviceId, TrustedDeviceStatus status) {
    switch (status) {
      case TrustedDeviceStatus.suspended:
        state = DeviceSuspended(deviceId);
      case TrustedDeviceStatus.revoked:
        state = DeviceRevoked(deviceId);
        unawaited(_clearLocalState());
      case TrustedDeviceStatus.retired:
        state = DeviceRetired(deviceId);
        unawaited(_clearLocalState());
      case TrustedDeviceStatus.active:
        // Only advance out of the pending/approval-watching states here —
        // never overwrites an already-active/expiring session (which this
        // same stream event fires on every registration doc change, not
        // just the pending->active transition).
        if (state is RegistrationRequested) {
          state = ActivationRequired(deviceId);
        }
      case TrustedDeviceStatus.pending:
        // No state change — still exactly where RegistrationRequested
        // already put us.
        break;
    }
  }

  Future<void> _clearLocalState() async {
    await keyStore.deleteKey(_namespace);
    await sessionCache.clearAll(_namespace);
  }

  /// Generates (or reuses) the local key pair and requests registration.
  /// Idempotent: calling this again after a successful call is a safe
  /// no-op that simply re-confirms the same registration
  /// (`alreadyRegistered: true`), never generating a second key.
  Future<void> register({required List<String> capabilities}) async {
    if (!keyStore.isPlatformSupported) {
      state = const UnsupportedPlatform();
      return;
    }
    try {
      final publicKeyPem = await keyStore.loadOrCreatePublicKeyPem(_namespace);
      final result = await sessionGateway.requestRegistration(
        organizationId: organizationId,
        branchId: branchId,
        platform: devicePlatformWireValue,
        publicKeyPem: publicKeyPem,
        capabilities: capabilities,
      );
      await sessionCache.writeDeviceId(_namespace, result.deviceId);
      _watchDeviceStatus(result.deviceId);
      if (result.status == 'active') {
        state = ActivationRequired(result.deviceId);
      } else {
        state = RegistrationRequested(
          result.deviceId,
          result.approvalRequestId ?? '',
        );
      }
    } on DeviceKeyStorageCorruptedException catch (e) {
      state = KeyStorageCorrupted(e.toString());
    } on TrustedDeviceSessionException catch (e) {
      if (e.code == 'failed-precondition' &&
          e.message.toLowerCase().contains('entitle')) {
        state = DeviceEntitlementDenied(e.message);
      } else {
        state = DeviceNetworkError(e.message);
      }
    }
  }

  /// Challenge + sign + issue — the proof-of-possession half. Called both
  /// for a first activation (from [ActivationRequired]) and for a refresh
  /// (from [ExpiringRefreshing]/an expired [ActiveSession]) — the server
  /// side is the exact same `requestDeviceChallenge`/`issueDeviceSession`
  /// pair either way (mirrors `trustedDevice.ts`'s own doc comment: no
  /// separate renew endpoint exists).
  Future<void> activateOrRefresh() async {
    final deviceId = switch (state) {
      ActivationRequired(:final deviceId) => deviceId,
      ActiveSession(:final deviceId) => deviceId,
      ExpiringRefreshing(:final deviceId) => deviceId,
      _ => null,
    };
    if (deviceId == null) return;

    final priorState = state;
    state = Activating(deviceId);
    try {
      final purpose = priorState is ActivationRequired ? 'issue' : 'renew';
      final challenge = await sessionGateway.requestChallenge(
        organizationId: organizationId,
        branchId: branchId,
        deviceId: deviceId,
        purpose: purpose,
      );
      final signature =
          await keyStore.signChallenge(_namespace, challenge.nonce);
      final session = await sessionGateway.issueSession(
        organizationId: organizationId,
        branchId: branchId,
        deviceId: deviceId,
        challengeId: challenge.challengeId,
        signature: signature,
      );
      await sessionCache.writeSession(
        _namespace,
        sessionId: session.sessionId,
        expiresAt: session.expiresAt,
      );
      state = ActiveSession(
        deviceId: deviceId,
        sessionId: session.sessionId,
        expiresAt: session.expiresAt,
      );
    } on DeviceKeyNotFoundException {
      state = const NotRegistered();
    } on DeviceKeyStorageCorruptedException catch (e) {
      state = KeyStorageCorrupted(e.toString());
    } on TrustedDeviceSessionException catch (e) {
      state = DeviceNetworkError(e.message);
    }
  }

  /// Called before any device-gated POS action — returns the still-valid
  /// session immediately if one exists, transparently refreshing first if
  /// within [_refreshLeadTime] of expiry. Throws if no session can be
  /// established (the caller — a POS action gateway — must surface this as
  /// its own explicit blocked state, never attempt the action anyway).
  Future<({String deviceId, String sessionId})> ensureFreshSession() async {
    final current = state;
    if (current is ActiveSession) {
      if (current.expiresAt.difference(DateTime.now()) > _refreshLeadTime) {
        return (deviceId: current.deviceId, sessionId: current.sessionId);
      }
      state = ExpiringRefreshing(
        deviceId: current.deviceId,
        sessionId: current.sessionId,
        expiresAt: current.expiresAt,
      );
      await activateOrRefresh();
    } else if (current is ExpiringRefreshing) {
      await activateOrRefresh();
    }
    final refreshed = state;
    if (refreshed is ActiveSession) {
      return (deviceId: refreshed.deviceId, sessionId: refreshed.sessionId);
    }
    throw StateError('No active trusted-device session is available.');
  }

  /// Operator-confirmed recovery from [KeyStorageCorrupted] or a terminal
  /// [DeviceRevoked]/[DeviceRetired] state — clears everything local and
  /// returns to [NotRegistered], ready for [register] to create a genuinely
  /// new identity. Never called automatically.
  Future<void> resetAndReregister() async {
    await _clearLocalState();
    _deviceStreamSub?.cancel();
    _deviceStreamSub = null;
    state = keyStore.isPlatformSupported
        ? const NotRegistered()
        : const UnsupportedPlatform();
  }

  @override
  void dispose() {
    _deviceStreamSub?.cancel();
    super.dispose();
  }
}
