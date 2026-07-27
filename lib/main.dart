import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'bootstrap/firebase_bootstrap_service.dart';
import 'bootstrap/firebase_ready_provider.dart';
import 'core/services/logging/logging_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isFirebaseReady = await FirebaseBootstrapService(
    loggingService: defaultLoggingService(),
  ).initialize();

  runApp(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(isFirebaseReady),
      ],
      child: const AbakusApp(),
    ),
  );
}
