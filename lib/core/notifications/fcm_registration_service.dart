import 'package:cloud_functions/cloud_functions.dart' as cloud_functions;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Faz R.3C/R.3C.1 — obtains/refreshes this device's real FCM token and
/// registers it via the `registerDeviceToken` Cloud Function callable, so
/// `reservationNotificationDelivery.ts`'s trigger has a real, current
/// token to target. This is the one seam in this codebase that actually
/// calls `firebase_messaging` — the package was already a declared
/// dependency (`pubspec.yaml`) with zero real references anywhere in
/// `lib/` before Faz R.3C.
///
/// **Faz R.3C.1 — routed through a server callable, not a direct Firestore
/// write.** R.3C originally called `RegisterDeviceToken`
/// (`core/device_tokens`) directly against `FirestoreDeviceTokenRepository`.
/// That could not actually detect a token already active under a
/// *different* customer in production: `firestore.rules`'s `deviceTokens`
/// read rule only ever lets a caller see their own documents, so a
/// different customer re-registering the same physical token would
/// silently create a second, duplicate-token document instead of
/// reassociating it — the client structurally cannot see across owners
/// the way this operation requires. `registerDeviceToken.ts` runs the
/// find-and-reassociate logic with the Admin SDK instead, which can.
/// [organizationId] is no longer part of this interface for the same
/// reason: the callable resolves it server-side, never from a client-
/// supplied value.
abstract interface class FcmRegistrationService {
  /// Requests notification permission (a silent no-op on platforms/OSes
  /// that don't prompt, e.g. Android <13), obtains the current token, and
  /// registers it for [uid] via the `registerDeviceToken` callable. Also
  /// subscribes to [FirebaseMessaging.onTokenRefresh] so a token FCM
  /// rotates later is re-registered without requiring the app to restart.
  /// Safe to call more than once, including for a different [uid] on the
  /// same physical device — that is exactly the cross-customer-
  /// reassociation path `registerDeviceToken.ts` handles server-side.
  Future<void> registerForUid({required String uid});
}

/// Real implementation — never constructed unless Firebase has finished
/// bootstrapping (see `fcm_registration_provider.dart`'s
/// [firebaseReadyProvider]-gated wiring), matching every other real-
/// Firebase-service constructor in this codebase.
class FirebaseFcmRegistrationService implements FcmRegistrationService {
  FirebaseFcmRegistrationService({
    FirebaseMessaging? messaging,
    cloud_functions.FirebaseFunctions? functions,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _functions = functions ?? cloud_functions.FirebaseFunctions.instance;

  final FirebaseMessaging _messaging;
  final cloud_functions.FirebaseFunctions _functions;
  bool _refreshListenerAttached = false;

  @override
  Future<void> registerForUid({required String uid}) async {
    await _messaging.requestPermission();

    final token = await _messaging.getToken();
    if (token != null) {
      await _registerRemote(token: token);
    }

    if (!_refreshListenerAttached) {
      _refreshListenerAttached = true;
      _messaging.onTokenRefresh.listen((refreshedToken) {
        _registerRemote(token: refreshedToken);
      });
    }
  }

  /// Best-effort: a failed registration only means this device misses
  /// push notifications, never a reason to disrupt the caller's own
  /// (typically auth-related) flow — mirrors this codebase's existing
  /// "device-token registration failure is not a security gap" framing
  /// (`device_token_repository.dart`).
  Future<void> _registerRemote({required String token}) async {
    final callable = _functions.httpsCallable('registerDeviceToken');
    try {
      await callable.call<Map<String, dynamic>>({
        'token': token,
        'platform': _platformName,
      });
    } on cloud_functions.FirebaseFunctionsException {
      // Swallowed deliberately — see doc comment above.
    }
  }

  /// Best-effort metadata only (`DeviceToken.platform`) — never used for
  /// authorization, so `defaultTargetPlatform`'s test/desktop fallbacks
  /// resolving to `'web'` is an acceptable simplification, not a
  /// correctness concern.
  String get _platformName {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'web';
    }
  }
}

/// No-op used whenever Firebase isn't ready — mirrors every other
/// `NoOp*Service` in this codebase (`NoOpCrashReportingService`, etc.).
class NoOpFcmRegistrationService implements FcmRegistrationService {
  const NoOpFcmRegistrationService();

  @override
  Future<void> registerForUid({required String uid}) async {}
}
