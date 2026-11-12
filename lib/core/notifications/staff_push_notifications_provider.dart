import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap/firebase_ready_provider.dart';
import 'staff_push_notifications.dart';

/// 2026-11-12 (Faz 3c) — real local notifications only on Android/iOS with
/// Firebase ready; a no-op on Windows (the POS keeps its live badge and
/// alert sound), on the web and in every `flutter test` run.
final staffPushNotificationsProvider = Provider<StaffPushNotifications>((ref) {
  final mobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (!mobile || !ref.watch(firebaseReadyProvider)) {
    return const NoOpStaffPushNotifications();
  }
  return LocalStaffPushNotifications();
});
