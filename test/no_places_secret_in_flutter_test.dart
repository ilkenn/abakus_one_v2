import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Faz P.2.1 §8 req 7 — a real, permanent regression guard: no Dart file
/// under `lib/` may ever reference the Google Places server secret name.
/// The secret is Cloud-Functions-only (`functions/src/deliveryPlaces.ts`'
/// `defineSecret("GOOGLE_PLACES_SERVER_KEY")`); the Flutter client never
/// sees the value, and this test also structurally rules out even the
/// *name* leaking into client source (e.g. an accidental hardcoded key
/// wired the same way it's named server-side, or a copy-pasted comment
/// containing the literal secret identifier in a context that could be
/// confused for real usage).
void main() {
  test('no lib/**/*.dart file references GOOGLE_PLACES_SERVER_KEY', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    final offendingFiles = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      if (content.contains('GOOGLE_PLACES_SERVER_KEY')) {
        offendingFiles.add(entity.path);
      }
    }

    expect(
      offendingFiles,
      isEmpty,
      reason: 'The Places server secret name must never appear in Flutter '
          'client source: ${offendingFiles.join(", ")}',
    );
  });
}
