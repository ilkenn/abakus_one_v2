import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../bootstrap/app_environment.dart';
import '../../../bootstrap/firebase_functions_emulator_config.dart';
import '../../../core/services/functions/rest_callable_client.dart';

/// The three real callables `trusted_device_gateway.dart` deliberately
/// excludes — AP-3 continuation. That file's own doc comment says exactly
/// why: registration is device-self-service, activation is never a direct
/// mutation. This gateway is that missing device-self-service half:
/// `requestDeviceRegistration`/`requestDeviceChallenge`/`issueDeviceSession`
/// (`functions/src/trustedDevice.ts`) — proof-of-possession, never a bare
/// device-id claim.
class RequestDeviceRegistrationResult {
  const RequestDeviceRegistrationResult({
    required this.deviceId,
    required this.status,
    required this.alreadyRegistered,
    this.approvalRequestId,
  });

  final String deviceId;
  final String status;
  final bool alreadyRegistered;
  final String? approvalRequestId;
}

class RequestDeviceChallengeResult {
  const RequestDeviceChallengeResult({
    required this.challengeId,
    required this.nonce,
    required this.expiresAt,
  });

  final String challengeId;
  final String nonce;
  final DateTime expiresAt;
}

class IssueDeviceSessionResult {
  const IssueDeviceSessionResult({
    required this.sessionId,
    required this.expiresAt,
    required this.deviceId,
  });

  final String sessionId;
  final DateTime expiresAt;
  final String deviceId;
}

class TrustedDeviceSessionException implements Exception {
  const TrustedDeviceSessionException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'TrustedDeviceSessionException($code): $message';
}

abstract interface class TrustedDeviceSessionGateway {
  /// [publicKeyPem] must be the SPKI-PEM form [DeviceKeyStore] produces —
  /// this gateway never generates or holds key material itself. The
  /// server derives [RequestDeviceRegistrationResult.deviceId] from the
  /// public key's own fingerprint; this method never sends a
  /// client-chosen device id.
  Future<RequestDeviceRegistrationResult> requestRegistration({
    required String organizationId,
    required String branchId,
    required String platform,
    required String publicKeyPem,
    required List<String> capabilities,
  });

  Future<RequestDeviceChallengeResult> requestChallenge({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String purpose,
  });

  Future<IssueDeviceSessionResult> issueSession({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String challengeId,
    required String signature,
  });
}

class FirebaseTrustedDeviceSessionGateway
    implements TrustedDeviceSessionGateway {
  FirebaseTrustedDeviceSessionGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw TrustedDeviceSessionException(
      error.code,
      error.message ?? 'İşlem gerçekleştirilemedi.',
    );
  }

  /// See `PosOperationalViewGateway`'s identical `_call` helper
  /// (`pos_operational_view_gateway.dart`) for the full rationale — this
  /// device session is a hard prerequisite for that gateway's own two
  /// callables (`requireActiveDeviceSession`, server-side), so the same
  /// Windows-plus-local-emulator REST bridge is needed here too (PC
  /// Yönetici İnceleme Modu, 2026-09-20).
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final useRest = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        FirebaseFunctionsEmulatorConfig.shouldUseEmulator(
            AppEnvironment.current);
    if (useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw TrustedDeviceSessionException(error.code, error.message);
      }
    }
    final callable = functions.FirebaseFunctions.instance.httpsCallable(name);
    try {
      final result = await callable.call<Map<String, dynamic>>(data);
      return result.data;
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<RequestDeviceRegistrationResult> requestRegistration({
    required String organizationId,
    required String branchId,
    required String platform,
    required String publicKeyPem,
    required List<String> capabilities,
  }) async {
    final data = await _call('requestDeviceRegistration', {
      'organizationId': organizationId,
      'branchId': branchId,
      'platform': platform,
      'publicKeyPem': publicKeyPem,
      'signatureAlgorithm': 'ed25519',
      'capabilities': capabilities,
    });
    return RequestDeviceRegistrationResult(
      deviceId: data['deviceId'] as String,
      status: data['status'] as String,
      alreadyRegistered: data['alreadyRegistered'] as bool,
      approvalRequestId: data['approvalRequestId'] as String?,
    );
  }

  @override
  Future<RequestDeviceChallengeResult> requestChallenge({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String purpose,
  }) async {
    final data = await _call('requestDeviceChallenge', {
      'organizationId': organizationId,
      'branchId': branchId,
      'deviceId': deviceId,
      'purpose': purpose,
    });
    return RequestDeviceChallengeResult(
      challengeId: data['challengeId'] as String,
      nonce: data['nonce'] as String,
      expiresAt: DateTime.parse(data['expiresAt'] as String),
    );
  }

  @override
  Future<IssueDeviceSessionResult> issueSession({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String challengeId,
    required String signature,
  }) async {
    final data = await _call('issueDeviceSession', {
      'organizationId': organizationId,
      'branchId': branchId,
      'deviceId': deviceId,
      'challengeId': challengeId,
      'signature': signature,
    });
    return IssueDeviceSessionResult(
      sessionId: data['sessionId'] as String,
      expiresAt: DateTime.parse(data['expiresAt'] as String),
      deviceId: data['deviceId'] as String,
    );
  }
}

/// Fail-closed fallback — mirrors this codebase's established convention.
class UnavailableTrustedDeviceSessionGateway
    implements TrustedDeviceSessionGateway {
  const UnavailableTrustedDeviceSessionGateway();

  Never _unavailable() => throw const TrustedDeviceSessionException(
        'unavailable',
        'Cihaz oturum sistemi şu anda kullanılamıyor.',
      );

  @override
  Future<RequestDeviceRegistrationResult> requestRegistration({
    required String organizationId,
    required String branchId,
    required String platform,
    required String publicKeyPem,
    required List<String> capabilities,
  }) async =>
      _unavailable();

  @override
  Future<RequestDeviceChallengeResult> requestChallenge({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String purpose,
  }) async =>
      _unavailable();

  @override
  Future<IssueDeviceSessionResult> issueSession({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String challengeId,
    required String signature,
  }) async =>
      _unavailable();
}
