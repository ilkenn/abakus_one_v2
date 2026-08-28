import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/device_key_store.dart';

import '../test_support/fake_secure_storage_platform.dart';

/// RFC 8410 §4 — the fixed 12-byte DER prefix every Ed25519
/// `SubjectPublicKeyInfo` starts with (mirrors the private constant in
/// `device_key_store.dart` — duplicated here deliberately, as an
/// independent proof rather than importing the implementation's own
/// constant and trivially matching it against itself).
const _ed25519SpkiDerPrefix = [
  0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
];

void main() {
  late FakeSecureStoragePlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakePlatform;
  });

  SecureDeviceKeyStore buildStore({bool isPlatformSupported = true}) {
    return SecureDeviceKeyStore(
      storage: const FlutterSecureStorage(),
      isPlatformSupported: isPlatformSupported,
    );
  }

  group('SecureDeviceKeyStore — key generation and PEM encoding', () {
    test(
        'generates a genuine Ed25519 key pair and returns a correctly '
        'RFC 8410-structured SPKI PEM', () async {
      final store = buildStore();
      final pem = await store.loadOrCreatePublicKeyPem('org-1_branch-1');

      expect(pem, startsWith('-----BEGIN PUBLIC KEY-----'));
      expect(pem.trimRight(), endsWith('-----END PUBLIC KEY-----'));

      final body = pem
          .replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '')
          .replaceAll('\n', '');
      final der = base64.decode(body);

      expect(der.length, 44, reason: '12-byte prefix + 32-byte raw key');
      expect(der.sublist(0, 12), _ed25519SpkiDerPrefix);
    });

    test('loadOrCreatePublicKeyPem is idempotent — a second call returns '
        'the SAME public key, never generating a new one', () async {
      final store = buildStore();
      final first = await store.loadOrCreatePublicKeyPem('org-1_branch-1');
      final second = await store.loadOrCreatePublicKeyPem('org-1_branch-1');

      expect(second, first);
    });

    test('two different namespaces get two independent key pairs',
        () async {
      final store = buildStore();
      final a = await store.loadOrCreatePublicKeyPem('org-1_branch-1');
      final b = await store.loadOrCreatePublicKeyPem('org-1_branch-2');

      expect(a, isNot(b));
    });

    test('an unsupported platform throws before touching storage at all',
        () async {
      final store = buildStore(isPlatformSupported: false);
      await expectLater(
        () => store.loadOrCreatePublicKeyPem('org-1_branch-1'),
        throwsA(isA<DeviceKeyUnsupportedPlatformException>()),
      );
      expect(await store.hasKey('org-1_branch-1'), false);
    });
  });

  group('SecureDeviceKeyStore — signing (backend-verification-compatible)',
      () {
    test(
        'signChallenge produces a signature the SAME Ed25519 public key '
        'verifies — the exact proof-of-possession property '
        '`trustedDevice.ts`\'s verifySignature relies on', () async {
      final store = buildStore();
      final pem = await store.loadOrCreatePublicKeyPem('org-1_branch-1');
      const nonce = 'a-real-server-issued-nonce-abc123';

      final signatureBase64 = await store.signChallenge('org-1_branch-1', nonce);

      // Independently re-derive the raw public key bytes from the PEM
      // (mirrors what a relying party parsing the PEM would do) and verify
      // with the `cryptography` package's own Ed25519 implementation —
      // the same signature format (raw 64-byte R||S, base64) Node's
      // `crypto.verify(null, data, publicKeyPem, signature)` consumes for
      // ed25519 (proven end-to-end against the REAL Node backend by
      // `functions/src/test/ap3E2E.test.ts`, which uses the identical
      // Node-side generateKeyPairSync("ed25519")/sign(null, ...) pair this
      // implementation is designed to interoperate with).
      final body = pem
          .replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '')
          .replaceAll('\n', '');
      final der = base64.decode(body);
      final rawPublicKeyBytes = der.sublist(12);

      final algorithm = Ed25519();
      final isValid = await algorithm.verify(
        utf8.encode(nonce),
        signature: Signature(
          base64.decode(signatureBase64),
          publicKey: SimplePublicKey(rawPublicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
      expect(isValid, true);
    });

    test('signing the SAME nonce twice produces a deterministic Ed25519 '
        'signature (Ed25519 is deterministic by design — no random nonce '
        'reuse risk the way ECDSA has)', () async {
      final store = buildStore();
      await store.loadOrCreatePublicKeyPem('org-1_branch-1');
      const nonce = 'fixed-nonce-value';

      final first = await store.signChallenge('org-1_branch-1', nonce);
      final second = await store.signChallenge('org-1_branch-1', nonce);

      expect(second, first);
    });

    test('a DIFFERENT nonce produces a DIFFERENT signature — proves the '
        'raw nonce bytes are actually being signed, not a constant',
        () async {
      final store = buildStore();
      await store.loadOrCreatePublicKeyPem('org-1_branch-1');

      final sigA = await store.signChallenge('org-1_branch-1', 'nonce-a');
      final sigB = await store.signChallenge('org-1_branch-1', 'nonce-b');

      expect(sigA, isNot(sigB));
    });

    test('signChallenge throws DeviceKeyNotFoundException when no key '
        'exists for the namespace yet', () async {
      final store = buildStore();
      await expectLater(
        () => store.signChallenge('never-registered', 'some-nonce'),
        throwsA(isA<DeviceKeyNotFoundException>()),
      );
    });
  });

  group('SecureDeviceKeyStore — corruption and deletion', () {
    test('unparseable stored key material throws '
        'DeviceKeyStorageCorruptedException, never silently regenerates a '
        'new key under the same namespace', () async {
      final store = buildStore();
      // Simulates corrupted storage directly, bypassing the store's own
      // write path — the store must detect this on the NEXT read, not
      // assume its own prior write is the only way data ever gets there.
      await const FlutterSecureStorage().write(
        key: 'trusted_device_key_org-1_branch-1',
        value: 'not-valid-json-at-all',
      );

      await expectLater(
        () => store.signChallenge('org-1_branch-1', 'nonce'),
        throwsA(isA<DeviceKeyStorageCorruptedException>()),
      );
      // The corrupted value is still there — proving nothing silently
      // overwrote it with a fresh key.
      expect(
        await const FlutterSecureStorage()
            .read(key: 'trusted_device_key_org-1_branch-1'),
        'not-valid-json-at-all',
      );
    });

    test('deleteKey removes the key; a subsequent loadOrCreatePublicKeyPem '
        'call genuinely generates a NEW, different key pair', () async {
      final store = buildStore();
      final original = await store.loadOrCreatePublicKeyPem('org-1_branch-1');
      await store.deleteKey('org-1_branch-1');
      expect(await store.hasKey('org-1_branch-1'), false);

      final regenerated = await store.loadOrCreatePublicKeyPem('org-1_branch-1');
      expect(regenerated, isNot(original));
    });
  });

  group('SecureDeviceKeyStore — private key never leaves the class', () {
    test('every value written to secure storage, JSON-decoded, has no '
        'field whose serialized string form appears in the returned '
        'public-key PEM or signature (a private key byte sequence never '
        'coincidentally equals its own public key or a signature)',
        () async {
      final store = buildStore();
      final pem = await store.loadOrCreatePublicKeyPem('org-1_branch-1');
      final signature = await store.signChallenge('org-1_branch-1', 'nonce');

      final storedRaw = fakePlatform.readAll(options: const {});
      final stored = await storedRaw;
      final storedJson = stored['trusted_device_key_org-1_branch-1']!;
      final decoded = jsonDecode(storedJson) as Map<String, dynamic>;
      expect(decoded.containsKey('privateKeyBytes'), true);

      // The only way this class's OWN public API (the PEM string, the
      // base64 signature) could leak the private key is if either
      // literally embedded the raw private key bytes as a substring —
      // trivially false for two cryptographically independent byte
      // sequences, asserted directly rather than assumed.
      final privateKeyBytes =
          (decoded['privateKeyBytes'] as List).cast<int>();
      final privateKeyBase64 = base64.encode(privateKeyBytes);
      expect(pem.contains(privateKeyBase64), false);
      expect(signature.contains(privateKeyBase64), false);
    });
  });
}
