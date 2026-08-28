import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../data/device_key_store.dart';
import '../../data/device_session_cache.dart';
import '../../data/trusted_device_session_gateway.dart';
import '../../application/use_cases/trusted_device_session_controller.dart';
import '../../domain/trusted_device/device_registration_state.dart';
import 'admin_dependencies_provider.dart';
import 'admin_context_provider.dart';

/// AP-3 continuation — the trusted-device Flutter provider wiring
/// (`docs/decisions.md` ADR-041). Mirrors this codebase's established
/// `firebaseReadyProvider`-gated real/`Unavailable` split throughout.

/// Resolved once, statelessly, from `defaultTargetPlatform`/[kIsWeb] —
/// mirrors `trustedDevice.ts`'s own `VALID_PLATFORMS` wire vocabulary
/// exactly. `web` is always `false` for [devicePlatformSupportedProvider]
/// (see that provider) even though it has its own wire value here, for the
/// same reason the server itself never resolves a web registration to
/// `PLATFORM_PROTECTED`.
final devicePlatformWireValueProvider = Provider<String>((ref) {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.linux:
      return 'linux'; // not a server-eligible platform; resolves unsupported below.
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
});

/// `true` only for a platform the server's own `PLATFORM_PROTECTED_ELIGIBLE`
/// set actually accepts — resolved client-side so a key is never generated
/// for a platform that could never use it (Web POS remains fail-closed by
/// construction: no key is ever created, `DeviceKeyStore
/// .loadOrCreatePublicKeyPem` is never called for it).
final devicePlatformSupportedProvider = Provider<bool>((ref) {
  final platform = ref.watch(devicePlatformWireValueProvider);
  return platform == 'android' ||
      platform == 'ios' ||
      platform == 'windows' ||
      platform == 'macos';
});

final deviceKeyStoreProvider = Provider<DeviceKeyStore>((ref) {
  return SecureDeviceKeyStore(
    isPlatformSupported: ref.watch(devicePlatformSupportedProvider),
  );
});

final deviceSessionCacheProvider = Provider<DeviceSessionCache>((ref) {
  return DeviceSessionCache();
});

final trustedDeviceSessionGatewayProvider =
    Provider<TrustedDeviceSessionGateway>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (isFirebaseReady) {
    return const FirebaseTrustedDeviceSessionGateway();
  }
  return const UnavailableTrustedDeviceSessionGateway();
});

/// Build-environment discriminator for on-device storage namespacing —
/// reuses the same `String.fromEnvironment`-driven flavor this app already
/// resolves for Firebase project selection, so a device key generated
/// under one environment is never mistakenly reused for another
/// environment's own backend. Falls back to `'dev'` (the existing
/// `kIsWeb`-independent default used elsewhere in this codebase's own
/// environment resolution) when no flavor is defined at build time.
final deviceStorageEnvironmentProvider = Provider<String>((ref) {
  const flavor = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
  return flavor;
});

/// One controller per (organizationId, branchId) pair — `.family` so
/// switching branches (a manager with multi-branch access) never mixes one
/// branch's device identity/session with another's.
final trustedDeviceSessionControllerProvider = StateNotifierProvider.family<
    TrustedDeviceSessionController,
    DeviceRegistrationState,
    ({String organizationId, String branchId})>((ref, args) {
  return TrustedDeviceSessionController(
    keyStore: ref.watch(deviceKeyStoreProvider),
    sessionCache: ref.watch(deviceSessionCacheProvider),
    sessionGateway: ref.watch(trustedDeviceSessionGatewayProvider),
    deviceRepository: ref.watch(trustedDeviceRepositoryProvider),
    organizationId: args.organizationId,
    branchId: args.branchId,
    environment: ref.watch(deviceStorageEnvironmentProvider),
    devicePlatformWireValue: ref.watch(devicePlatformWireValueProvider),
  );
});

/// Which branch this device is being registered for / operates as —
/// operator-selected (this app's UI defaults it to the signed-in staff
/// actor's first accessible branch, then lets them change it before
/// registration; `null` until a real branch list has resolved).
///
/// Deliberately NOT [deviceBoundBranchIdProvider] (`admin_context_provider
/// .dart`): that provider's own doc comment already declares it a
/// placeholder for "separate, later work" — reflecting an ALREADY-ACTIVE
/// device's bound branch back into the context switcher, which requires
/// enumerating every branch-scoped controller instance this staff member
/// could have, a genuinely separate concern from "which branch should a
/// not-yet-registered device register itself against." This provider is
/// this feature's own, narrower, real answer to the second question only.
final selectedPosBranchIdProvider = StateProvider<String?>((ref) => null);

/// The current admin session's own organization + selected branch — the
/// controller args this screen should actually use. `null` while context
/// or branch selection hasn't resolved yet — callers must handle that
/// before rendering any trusted-device UI, exactly like every other
/// branch-scoped Admin screen already does.
final currentTrustedDeviceSessionControllerProvider = Provider<
    ({String organizationId, String branchId})?>((ref) {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  final branchId = ref.watch(selectedPosBranchIdProvider);
  if (branchId == null) return null;
  return (organizationId: organizationId, branchId: branchId);
});
