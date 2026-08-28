import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Real Ed25519 device-key generation, storage, and challenge signing —
/// AP-3 continuation (`docs/decisions.md` ADR-041). Backs the trusted-device
/// POS flow's proof-of-possession half of `functions/src/trustedDevice.ts`.
///
/// **Trust level — honest, never overstated.** This is `PLATFORM_PROTECTED`:
/// the private key lives in OS-encrypted-at-rest storage
/// (`flutter_secure_storage` — Android Keystore-backed EncryptedSharedPreferences/
/// iOS Keychain/Windows DPAPI/macOS Keychain), decrypted into process memory
/// only for the moment a signature is produced. It is NOT
/// `HARDWARE_ATTESTED`: there is no Play Integrity/App Attest attestation
/// proving the key was generated inside a secure enclave and never existed
/// in software-accessible memory, and no non-exportable hardware-backed key
/// object is used. The server independently derives the same conclusion
/// (`trustedDevice.ts`'s own `PLATFORM_PROTECTED_ELIGIBLE` resolution) —
/// this class's honesty is a property this code enforces by construction
/// (it never claims a tier), not merely by convention.
///
/// **Never exposes the raw private key outside this class.** Every public
/// method here returns either a public key (safe to send to the server) or
/// a signature (safe to send to the server) — never
/// [SimpleKeyPairData.extractPrivateKeyBytes]'s own return value. No
/// method here logs, serializes, or otherwise lets private key material
/// escape this class's own local scope.
abstract interface class DeviceKeyStore {
  /// `true` only for a platform `trustedDevice.ts`'s own
  /// `PLATFORM_PROTECTED_ELIGIBLE` set actually accepts — resolved
  /// entirely client-side, before any network call or key generation.
  bool get isPlatformSupported;

  /// Returns the existing key's public key (PEM-encoded SPKI, matching
  /// exactly what `requestDeviceRegistration`'s `publicKeyPem` expects) if
  /// one is already stored for [namespace], or generates and persists a
  /// new Ed25519 key pair and returns its public key otherwise.
  ///
  /// Throws [DeviceKeyStorageCorruptedException] if storage holds
  /// unparseable key material — never silently discards it and generates a
  /// replacement (see this file's own doc comment).
  Future<String> loadOrCreatePublicKeyPem(String namespace);

  /// Signs [nonce]'s raw UTF-8 bytes (mirrors `trustedDevice.ts`'s own
  /// `verifySignature`: `Buffer.from(nonce, "utf8")`, no additional
  /// canonicalization) with the stored private key for [namespace],
  /// returning the raw 64-byte Ed25519 signature, base64-encoded.
  ///
  /// Throws [DeviceKeyNotFoundException] if no key exists for [namespace]
  /// (call [loadOrCreatePublicKeyPem] first) or
  /// [DeviceKeyStorageCorruptedException] if storage holds unparseable key
  /// material.
  Future<String> signChallenge(String namespace, String nonce);

  /// Permanently deletes the stored key for [namespace] — the deliberate,
  /// operator-confirmed recovery path for a revoked/retired device or a
  /// detected storage corruption; never called automatically.
  Future<void> deleteKey(String namespace);

  /// `true` if a key currently exists for [namespace] (does not validate
  /// it parses — use [loadOrCreatePublicKeyPem]/[signChallenge] for that).
  Future<bool> hasKey(String namespace);
}

class DeviceKeyNotFoundException implements Exception {
  const DeviceKeyNotFoundException(this.namespace);
  final String namespace;
  @override
  String toString() => 'DeviceKeyNotFoundException: no key for $namespace';
}

class DeviceKeyStorageCorruptedException implements Exception {
  const DeviceKeyStorageCorruptedException(this.namespace, this.message);
  final String namespace;
  final String message;
  @override
  String toString() =>
      'DeviceKeyStorageCorruptedException: $namespace ($message)';
}

class DeviceKeyUnsupportedPlatformException implements Exception {
  const DeviceKeyUnsupportedPlatformException();
  @override
  String toString() => 'DeviceKeyUnsupportedPlatformException';
}

/// RFC 8410 §4 — the fixed 12-byte DER prefix for an Ed25519
/// `SubjectPublicKeyInfo` (`AlgorithmIdentifier` for id-Ed25519, OID
/// 1.3.101.112, no parameters, followed by a BIT STRING header for the
/// 32-byte raw public key). Every Ed25519 SPKI differs only in its final
/// 32 bytes — this constant is not derived per-key, it's the fixed
/// structural header RFC 8410 specifies for every Ed25519 public key.
const List<int> _ed25519SpkiDerPrefix = [
  0x30,
  0x2a,
  0x30,
  0x05,
  0x06,
  0x03,
  0x2b,
  0x65,
  0x70,
  0x03,
  0x21,
  0x00,
];

String _ed25519PublicKeyToSpkiPem(List<int> rawPublicKeyBytes) {
  if (rawPublicKeyBytes.length != 32) {
    throw ArgumentError(
      'An Ed25519 public key must be exactly 32 bytes, got ${rawPublicKeyBytes.length}.',
    );
  }
  final der = Uint8List.fromList([
    ..._ed25519SpkiDerPrefix,
    ...rawPublicKeyBytes,
  ]);
  final base64Body = base64.encode(der);
  final wrapped = StringBuffer();
  for (var i = 0; i < base64Body.length; i += 64) {
    wrapped.writeln(
      base64Body.substring(
          i, i + 64 > base64Body.length ? base64Body.length : i + 64),
    );
  }
  return '-----BEGIN PUBLIC KEY-----\n$wrapped-----END PUBLIC KEY-----\n';
}

/// The real, platform-native implementation — [FlutterSecureStorage] for
/// at-rest encryption, `package:cryptography`'s pure-Dart [Ed25519] (with
/// `cryptography_flutter`'s platform-accelerated implementation enabled at
/// app startup, `lib/bootstrap/app_bootstrap.dart` — transparent to this
/// class, it always calls the same `Ed25519()` API regardless of which
/// backend actually executes) for key generation and signing.
///
/// Storage keys are namespaced by an explicit [namespace] string the
/// caller controls (this app namespaces by
/// `{environment}_{organizationId}_{branchId}` — never by the
/// server-derived `deviceId`, which doesn't exist until AFTER the first
/// key is generated and registered) — never a bare, environment-agnostic
/// key name, which would risk a dev/staging/production key collision on a
/// shared device.
class SecureDeviceKeyStore implements DeviceKeyStore {
  SecureDeviceKeyStore({
    FlutterSecureStorage? storage,
    this.isPlatformSupported = true,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  final bool isPlatformSupported;

  static final _algorithm = Ed25519();

  String _storageKey(String namespace) => 'trusted_device_key_$namespace';

  Future<SimpleKeyPairData> _loadKeyPairData(String namespace) async {
    final raw = await _storage.read(key: _storageKey(namespace));
    if (raw == null) throw DeviceKeyNotFoundException(namespace);
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final privateKeyBytes = (decoded['privateKeyBytes'] as List).cast<int>();
      final publicKeyBytes = (decoded['publicKeyBytes'] as List).cast<int>();
      return SimpleKeyPairData(
        privateKeyBytes,
        publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      );
    } catch (e) {
      throw DeviceKeyStorageCorruptedException(namespace, e.toString());
    }
  }

  @override
  Future<bool> hasKey(String namespace) async {
    return (await _storage.read(key: _storageKey(namespace))) != null;
  }

  @override
  Future<String> loadOrCreatePublicKeyPem(String namespace) async {
    if (!isPlatformSupported) {
      throw const DeviceKeyUnsupportedPlatformException();
    }
    final existingRaw = await _storage.read(key: _storageKey(namespace));
    if (existingRaw != null) {
      final data = await _loadKeyPairData(namespace);
      final publicKey = await data.extractPublicKey();
      return _ed25519PublicKeyToSpkiPem(publicKey.bytes);
    }

    final keyPair = await _algorithm.newKeyPair();
    final keyPairData = await keyPair.extract();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    // Minimizes the private key's own lifetime in a named local — written
    // straight into the JSON payload handed to secure storage, never
    // retained in an instance field or any longer-lived structure.
    final payload = jsonEncode({
      'privateKeyBytes': privateKeyBytes,
      'publicKeyBytes': publicKey.bytes,
    });
    await _storage.write(key: _storageKey(namespace), value: payload);
    // Best-effort clear of the local reference; Dart has no way to
    // guarantee zeroing GC'd memory, but this at least drops the only
    // named handle to it as early as possible.
    keyPairData.destroy();

    return _ed25519PublicKeyToSpkiPem(publicKey.bytes);
  }

  @override
  Future<String> signChallenge(String namespace, String nonce) async {
    if (!isPlatformSupported) {
      throw const DeviceKeyUnsupportedPlatformException();
    }
    final keyPairData = await _loadKeyPairData(namespace);
    final signature = await _algorithm.sign(
      utf8.encode(nonce),
      keyPair: keyPairData,
    );
    keyPairData.destroy();
    return base64.encode(signature.bytes);
  }

  @override
  Future<void> deleteKey(String namespace) async {
    await _storage.delete(key: _storageKey(namespace));
  }
}
