import 'package:firebase_core/firebase_core.dart';

import '../../bootstrap/app_environment.dart';
import '../../firebase_options.dart' as production_options;
import '../../firebase_options_development.dart' as development_options;
import '../../firebase_options_staging.dart' as staging_options;

/// Resolves which of the three FlutterFire-CLI-generated option sets
/// (`lib/firebase_options.dart` = production, `firebase_options_development
/// .dart`, `firebase_options_staging.dart`) applies to a given
/// [AppEnvironment] — the one place `AppEnvironment` and a concrete Firebase
/// project meet.
///
/// Every generated file defines a class named `DefaultFirebaseOptions`
/// (FlutterFire CLI's own convention) — imported here under a per-file
/// prefix so the three don't collide, and never re-exported or edited.
/// Generated files stay exactly as FlutterFire CLI produced them; if a
/// project needs reconfiguring, re-run `flutterfire configure` against that
/// file, don't hand-edit its contents.
///
/// [forEnvironment]'s `switch` is exhaustive over all three
/// [AppEnvironment] values with no `default`/fallback branch, so an
/// environment this selector doesn't recognize is a compile error, not a
/// silent fall-through to production. Combined with [AppEnvironment
/// .fromDefine] already defaulting an unrecognized `--dart-define` string to
/// [AppEnvironment.development] *before* it ever reaches this selector, an
/// unknown environment can reach neither this switch nor production by any
/// path — two independent layers, not one.
abstract final class FirebaseOptionsSelector {
  FirebaseOptionsSelector._();

  static FirebaseOptions forEnvironment(AppEnvironment environment) {
    switch (environment) {
      case AppEnvironment.development:
        return development_options.DefaultFirebaseOptions.currentPlatform;
      case AppEnvironment.staging:
        return staging_options.DefaultFirebaseOptions.currentPlatform;
      case AppEnvironment.production:
        return production_options.DefaultFirebaseOptions.currentPlatform;
    }
  }
}
