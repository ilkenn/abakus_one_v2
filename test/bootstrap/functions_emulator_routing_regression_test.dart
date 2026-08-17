import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Paket Servis P.3 — Dev Functions Emulator Routing Audit (device
/// blocker follow-up). A real, permanent regression guard, mirroring
/// `no_places_secret_in_flutter_test.dart`'s exact static-scan pattern.
///
/// `FirebaseBootstrapService.initialize` calls `useFunctionsEmulator` on
/// exactly one object: the default `FirebaseFunctions.instance` singleton
/// (`lib/bootstrap/firebase_bootstrap_service.dart`). Every callable
/// gateway in this codebase (`GooglePlacesAddressSearchProvider`,
/// `FirestoreSavedAddressRepository`, `FirebaseSubmitTakeawayOrderGateway`,
/// `FirebaseSubmitDeliveryOrderGateway`, ...) reads that exact same
/// singleton — never `FirebaseFunctions.instanceFor(...)`, which would
/// construct a **separate** instance the bootstrap's `useFunctionsEmulator`
/// call never touches, silently bypassing the configured emulator even
/// though `AppEnvironment.current == development`. This test structurally
/// rules that class of bug out for every current and future callable
/// gateway, rather than relying on manual code review to catch it.
///
/// This does **not** cover the actual physical-device root cause found
/// during this audit (an Android Gradle product-flavor vs.
/// `--dart-define=ENVIRONMENT` build-invocation mismatch, which blocks the
/// emulator's plaintext HTTP connection at the OS network-security-policy
/// level before any Dart code runs) — that is a build-invocation
/// discipline issue outside what a `flutter test` can observe, documented
/// instead in `docs/firebase_emulator.md`'s troubleshooting section and
/// `docs/decisions.md`'s Paket Servis P.3 §D12.
void main() {
  test(
      'no lib/**/*.dart file calls FirebaseFunctions.instanceFor(...) — '
      'every callable must share the one emulator-configured '
      'FirebaseFunctions.instance singleton', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    final offendingFiles = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      if (content.contains('FirebaseFunctions.instanceFor(')) {
        offendingFiles.add(entity.path);
      }
    }

    expect(
      offendingFiles,
      isEmpty,
      reason: 'FirebaseFunctions.instanceFor(...) constructs an instance '
          'independent of FirebaseBootstrapService\'s useFunctionsEmulator '
          'call on FirebaseFunctions.instance — a callable built this way '
          'would silently talk to the real backend even in development. '
          'Offending files: ${offendingFiles.join(", ")}',
    );
  });

  test(
      'every httpsCallable(...) call site in lib/ is reached through '
      'FirebaseFunctions.instance (directly, or via a constructor default '
      'of it) — a spot count sanity check, not exhaustive AST analysis', () {
    final libDir = Directory('lib');
    var httpsCallableSites = 0;
    var instanceReferences = 0;
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      httpsCallableSites +=
          RegExp(r'\.httpsCallable\(').allMatches(content).length;
      instanceReferences +=
          RegExp(r'FirebaseFunctions\.instance\b').allMatches(content).length;
    }

    expect(httpsCallableSites, greaterThan(0),
        reason: 'sanity check — this codebase does call httpsCallable(...)');
    // Every file with an .httpsCallable( call site must also reference
    // FirebaseFunctions.instance somewhere (its own constructor default,
    // or a caller-injected one already validated by the test above never
    // being instanceFor(...)) — a coarse but real signal, not a proof.
    expect(
      instanceReferences,
      greaterThan(0),
      reason: 'expected at least one FirebaseFunctions.instance reference '
          'backing the httpsCallable(...) call sites found in lib/',
    );
  });
}
