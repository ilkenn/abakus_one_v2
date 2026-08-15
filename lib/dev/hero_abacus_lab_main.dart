import 'package:flutter/material.dart';
import 'hero_abacus_lab_screen.dart';

/// A second, isolated entrypoint — run directly via
/// `flutter run -t lib/dev/hero_abacus_lab_main.dart` — for developing
/// and reviewing the Hero Abacus signature object on a real device.
///
/// Deliberately does **not** call `bootstrapApp()` and has no
/// `ProviderScope`, router, or auth involvement at all: this is the
/// safest possible way to keep Hero Abacus Lab work fully isolated from
/// the real app, per the explicit "the existing login/authentication
/// system must remain untouched" requirement — nothing in `main.dart`,
/// `app_router.dart`, `app_routes.dart`, or any auth/onboarding file is
/// touched or imported by this entrypoint.
void main() {
  runApp(const _HeroAbacusLabApp());
}

class _HeroAbacusLabApp extends StatelessWidget {
  const _HeroAbacusLabApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HeroAbacusLabScreen(),
    );
  }
}
