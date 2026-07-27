import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'bootstrap/app_bootstrap.dart';

Future<void> main() async {
  final bootstrap = await bootstrapApp();

  runApp(
    ProviderScope(
      overrides: bootstrap.providerOverrides,
      child: const AbakusApp(),
    ),
  );
}
