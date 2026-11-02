import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'app.dart';
import 'bootstrap/app_bootstrap.dart';

Future<void> main() async {
  // 2026-10-29 — web only (a no-op on every other platform): without this,
  // Flutter web defaults to hash-based URLs ('/#/table/<token>'), so a real
  // QR/deep link to a path like '/table/<token>' loses that path segment
  // entirely on first load — go_router sees `/`, not the real route, and
  // `AppRouteGuard`'s `/table` exemption never even gets a chance to match.
  usePathUrlStrategy();

  final bootstrap = await bootstrapApp();

  runApp(
    ProviderScope(
      overrides: bootstrap.providerOverrides,
      child: const AbakusApp(),
    ),
  );
}
