import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Profile P.4.3A — Physical Storage Upload Failure Diagnostic
/// (2026-08-19). Mirrors `functions_emulator_routing_regression_test.dart`'s
/// exact static-scan pattern for the analogous Storage bug class.
///
/// `FirebaseBootstrapService.initialize` calls `useStorageEmulator` on
/// exactly one object: the default `FirebaseStorage.instance` singleton
/// (`lib/bootstrap/firebase_bootstrap_service.dart`). Every Storage caller
/// in this codebase (`FirebaseCustomerPhotoStorageClient`, ...) must read
/// that exact same singleton — never `FirebaseStorage.instanceFor(...)`,
/// which would construct a **separate** instance the bootstrap's
/// `useStorageEmulator` call never touches, silently bypassing the
/// configured emulator even though `AppEnvironment.current == development`.
/// This test structurally rules that class of bug out for every current
/// and future Storage caller, rather than relying on manual code review.
///
/// This does **not** by itself prove a physical Android device is actually
/// reachable at the configured emulator host — only that the Dart-side
/// instance selection is correct. See `docs/firebase_emulator.md`'s
/// troubleshooting section for the separate `adb reverse tcp:9199
/// tcp:9199` port-forwarding requirement, which this test cannot observe.
/// Strips `//`, `///`, `*`, and `/*`-prefixed lines before scanning —
/// this file's own target, `customer_photo_storage_client.dart`, legitimately
/// documents the forbidden `FirebaseStorage.instanceFor(...)` pattern in a
/// doc comment explaining why it must never be used; a raw substring scan
/// would false-positive on that explanation. Mirrors the identical fix
/// already applied to this codebase's other structural source-scan tests.
String _stripCommentLines(String source) {
  return source.split('\n').where((line) {
    final trimmed = line.trimLeft();
    return !trimmed.startsWith('//') &&
        !trimmed.startsWith('///') &&
        !trimmed.startsWith('*') &&
        !trimmed.startsWith('/*');
  }).join('\n');
}

void main() {
  test(
      'no lib/**/*.dart file calls FirebaseStorage.instanceFor(...) — '
      'every Storage caller must share the one emulator-configured '
      'FirebaseStorage.instance singleton', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    final offendingFiles = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = _stripCommentLines(entity.readAsStringSync());
      if (content.contains('FirebaseStorage.instanceFor(')) {
        offendingFiles.add(entity.path);
      }
    }

    expect(
      offendingFiles,
      isEmpty,
      reason: 'FirebaseStorage.instanceFor(...) constructs an instance '
          'independent of FirebaseBootstrapService\'s useStorageEmulator '
          'call on FirebaseStorage.instance — a caller built this way '
          'would silently talk to production Storage even in development. '
          'Offending files: ${offendingFiles.join(", ")}',
    );
  });

  test(
      'every .ref(...) Storage call site in lib/ is reached through '
      'FirebaseStorage.instance (directly, or via a constructor default '
      'of it) — a spot count sanity check, not exhaustive AST analysis', () {
    final libDir = Directory('lib');
    var storageRefSites = 0;
    var instanceReferences = 0;
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      if (!content.contains('firebase_storage')) continue;
      storageRefSites += RegExp(r'_storage\.ref\(').allMatches(content).length;
      instanceReferences +=
          RegExp(r'FirebaseStorage\.instance\b').allMatches(content).length;
    }

    expect(storageRefSites, greaterThan(0),
        reason: 'sanity check — this codebase does call Storage .ref(...)');
    expect(
      instanceReferences,
      greaterThan(0),
      reason: 'expected at least one FirebaseStorage.instance reference '
          'backing the Storage .ref(...) call sites found in lib/',
    );
  });
}
