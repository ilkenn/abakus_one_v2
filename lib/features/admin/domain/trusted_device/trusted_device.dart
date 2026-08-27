/// AP-2 final wiring — the real trusted-device domain model, mirroring
/// `functions/src/trustedDevice.ts`'s `DeviceRegistrationDoc` field-for-
/// field, with one deliberate omission: `publicKeyPem`/`publicKeyFingerprint`
/// are never carried into this client-side model at all — the UI has no
/// legitimate reason to hold a device's key material in memory, and this
/// is the structural way "no sensitive key/challenge/session information
/// in the UI" is enforced (there is no field to accidentally render).
library;

enum TrustedDeviceStatus { pending, active, suspended, revoked, retired }

enum TrustedDeviceTrustTier {
  hardwareAttested,
  platformProtected,
  unsupportedOrUntrusted,
}

enum TrustedDevicePlatform { android, ios, windows, macos, web }

enum TrustedDeviceCapability { pos, kds, printerController }

TrustedDeviceStatus trustedDeviceStatusFromWire(String value) {
  switch (value) {
    case 'pending':
      return TrustedDeviceStatus.pending;
    case 'active':
      return TrustedDeviceStatus.active;
    case 'suspended':
      return TrustedDeviceStatus.suspended;
    case 'revoked':
      return TrustedDeviceStatus.revoked;
    case 'retired':
      return TrustedDeviceStatus.retired;
    default:
      throw ArgumentError('Unknown trusted device status: $value');
  }
}

TrustedDeviceTrustTier trustedDeviceTrustTierFromWire(String value) {
  switch (value) {
    case 'HARDWARE_ATTESTED':
      return TrustedDeviceTrustTier.hardwareAttested;
    case 'PLATFORM_PROTECTED':
      return TrustedDeviceTrustTier.platformProtected;
    case 'UNSUPPORTED_OR_UNTRUSTED':
      return TrustedDeviceTrustTier.unsupportedOrUntrusted;
    default:
      throw ArgumentError('Unknown trust tier: $value');
  }
}

TrustedDevicePlatform trustedDevicePlatformFromWire(String value) {
  switch (value) {
    case 'android':
      return TrustedDevicePlatform.android;
    case 'ios':
      return TrustedDevicePlatform.ios;
    case 'windows':
      return TrustedDevicePlatform.windows;
    case 'macos':
      return TrustedDevicePlatform.macos;
    case 'web':
      return TrustedDevicePlatform.web;
    default:
      throw ArgumentError('Unknown device platform: $value');
  }
}

TrustedDeviceCapability trustedDeviceCapabilityFromWire(String value) {
  switch (value) {
    case 'POS':
      return TrustedDeviceCapability.pos;
    case 'KDS':
      return TrustedDeviceCapability.kds;
    case 'PRINTER_CONTROLLER':
      return TrustedDeviceCapability.printerController;
    default:
      throw ArgumentError('Unknown device capability: $value');
  }
}

class TrustedDevice {
  const TrustedDevice({
    required this.deviceId,
    required this.organizationId,
    required this.branchId,
    required this.platform,
    required this.capabilities,
    required this.status,
    required this.trustTier,
    required this.registeredByUid,
    required this.registeredAt,
    this.activatedAt,
    this.lastSeenAt,
    this.revokedAt,
    this.revokedReason,
    required this.version,
  });

  final String deviceId;
  final String organizationId;
  final String branchId;
  final TrustedDevicePlatform platform;
  final List<TrustedDeviceCapability> capabilities;
  final TrustedDeviceStatus status;
  final TrustedDeviceTrustTier trustTier;
  final String registeredByUid;
  final DateTime registeredAt;
  final DateTime? activatedAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;
  final String? revokedReason;
  final int version;

  /// Only these two transitions have a real callable behind them today —
  /// used by the UI to decide which action buttons are even meaningful to
  /// offer, matching `trustedDevice.ts`'s own real transition set exactly
  /// (no "reactivate" exists server-side for suspended, and revoke/retire
  /// are each independently idempotent no-ops once already terminal).
  bool get canBeSuspended =>
      status != TrustedDeviceStatus.suspended &&
      status != TrustedDeviceStatus.revoked &&
      status != TrustedDeviceStatus.retired;
  bool get canBeRevoked =>
      status != TrustedDeviceStatus.revoked &&
      status != TrustedDeviceStatus.retired;
  bool get canBeRetired => status != TrustedDeviceStatus.retired;
}
