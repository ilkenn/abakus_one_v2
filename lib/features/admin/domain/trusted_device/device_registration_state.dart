import 'trusted_device.dart';

/// The trusted-device POS UX's own client-side state machine — AP-3
/// continuation. Deliberately separate from [TrustedDeviceStatus] (the
/// server's own registration status): this state also has to represent
/// purely-local conditions the server has no concept of at all
/// (`unsupportedPlatform`, `keyStorageCorrupted`, `networkError`), and two
/// states ([registrationRequested]/[activating]) that are transient
/// client-side phases of a single server-side `pending` status.
sealed class DeviceRegistrationState {
  const DeviceRegistrationState();
}

/// This platform has never been eligible for a trusted-device session —
/// resolved purely client-side, before any network call, from
/// `defaultTargetPlatform`/`kIsWeb`. Mirrors the server's own
/// `PLATFORM_PROTECTED_ELIGIBLE` set (`trustedDevice.ts`) — web is never
/// eligible; the server would reject it anyway, but failing closed locally
/// means no key is ever generated or persisted for a platform that can
/// never use it.
final class UnsupportedPlatform extends DeviceRegistrationState {
  const UnsupportedPlatform();
}

/// No local key pair and no server registration exist yet for this
/// organization/branch.
final class NotRegistered extends DeviceRegistrationState {
  const NotRegistered();
}

/// The key pair was generated and `requestDeviceRegistration` succeeded;
/// waiting for the resulting `deviceActivation` approval request to be
/// resolved by a manager (via the existing Approval Inbox — this screen
/// never re-implements approval).
final class RegistrationRequested extends DeviceRegistrationState {
  const RegistrationRequested(this.deviceId, this.approvalRequestId);
  final String deviceId;
  final String approvalRequestId;
}

/// The manager has approved the device (`trustedDeviceRegistrations.status
/// == "active"`, observed via the existing staff-facing device stream) but
/// no session has been issued yet — the operator must trigger activation
/// (challenge + sign + issue) explicitly.
final class ActivationRequired extends DeviceRegistrationState {
  const ActivationRequired(this.deviceId);
  final String deviceId;
}

/// Mid-flight: requesting a challenge, signing it, and exchanging it for a
/// session.
final class Activating extends DeviceRegistrationState {
  const Activating(this.deviceId);
  final String deviceId;
}

/// A valid, unexpired session exists — POS operations may proceed.
final class ActiveSession extends DeviceRegistrationState {
  const ActiveSession({
    required this.deviceId,
    required this.sessionId,
    required this.expiresAt,
  });
  final String deviceId;
  final String sessionId;
  final DateTime expiresAt;
}

/// The session is within its refresh window (a fixed lead time before
/// [ActiveSession.expiresAt]) and a silent re-issue is in progress — POS
/// operations may still proceed using the still-valid session while this
/// resolves in the background.
final class ExpiringRefreshing extends DeviceRegistrationState {
  const ExpiringRefreshing({
    required this.deviceId,
    required this.sessionId,
    required this.expiresAt,
  });
  final String deviceId;
  final String sessionId;
  final DateTime expiresAt;
}

/// The server-side registration is `suspended` — a manager decision, no
/// self-service recovery (mirrors `trustedDevice.ts`'s own "no reactivate
/// callable" design).
final class DeviceSuspended extends DeviceRegistrationState {
  const DeviceSuspended(this.deviceId);
  final String deviceId;
}

/// The server-side registration is `revoked` — terminal; the local key is
/// deleted and a fresh registration (new key pair, new deviceId) is the
/// only recovery path — never silently generating a new key under the same
/// identity.
final class DeviceRevoked extends DeviceRegistrationState {
  const DeviceRevoked(this.deviceId);
  final String deviceId;
}

/// The server-side registration is `retired` — terminal end-of-life.
final class DeviceRetired extends DeviceRegistrationState {
  const DeviceRetired(this.deviceId);
  final String deviceId;
}

/// Secure storage returned corrupt/unparseable key material — never
/// silently regenerates a key for what might still be a legitimately
/// registered device (that would desynchronize the server's stored public
/// key from what this app can actually sign with, permanently locking the
/// device out even though its registration looks fine). Requires an
/// explicit, operator-confirmed re-registration.
final class KeyStorageCorrupted extends DeviceRegistrationState {
  const KeyStorageCorrupted(this.message);
  final String message;
}

/// A network/backend call failed transiently — retryable, never a terminal
/// state change.
final class DeviceNetworkError extends DeviceRegistrationState {
  const DeviceNetworkError(this.message);
  final String message;
}

/// The organization does not currently hold the entitlement
/// (`pos`/`kds`) this device capability requires — server-verified
/// (`requireModuleEntitlement`), never assumed client-side.
final class DeviceEntitlementDenied extends DeviceRegistrationState {
  const DeviceEntitlementDenied(this.message);
  final String message;
}
