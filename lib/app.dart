import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bootstrap/firebase_ready_provider.dart';
import 'core/auth/real_customer_check.dart';
import 'core/notifications/courier_push_tap_router.dart';
import 'core/notifications/fcm_registration_provider.dart';
import 'core/notifications/reservation_notification_tap_router.dart';
import 'core/notifications/staff_push_notifications_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/branding/presentation/providers/resolved_app_theme_provider.dart';
import 'features/pos/domain/authorization/actor_session.dart';
import 'features/pos/presentation/providers/actor_session_provider.dart';

class AbakusApp extends ConsumerStatefulWidget {
  const AbakusApp({super.key});

  @override
  ConsumerState<AbakusApp> createState() => _AbakusAppState();
}

class _AbakusAppState extends ConsumerState<AbakusApp> {
  StreamSubscription<RemoteMessage>? _notificationTapSubscription;
  ProviderSubscription<AuthState>? _authSubscription;
  bool _registeredThisSession = false;

  // 2026-11-12 (Faz 3c) — staff/courier push (ADR-078): the signed-in staff
  // account's device is registered for FCM (once per uid), and a courier-
  // pool push arriving in the foreground is shown as a system notification.
  ProviderSubscription<ActorSession?>? _staffSessionSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  String? _registeredStaffUid;

  @override
  void initState() {
    super.initState();
    // Faz R.3C — deliberately not part of `bootstrapApp()`'s pre-`runApp`
    // sequence (`lib/bootstrap/app_bootstrap.dart`): device-token
    // registration needs a resolved customer [AuthState] and is not
    // routing-critical, so doing it here (once the app is already
    // running) keeps the carefully-sequenced startup path unchanged.
    if (!ref.read(firebaseReadyProvider)) return;

    _authSubscription =
        ref.listenManual<AuthState>(authProvider, (previous, next) {
      _maybeRegisterDeviceToken(next);
    });
    _maybeRegisterDeviceToken(ref.read(authProvider));

    // The official `firebase_messaging` plugin ships no native Windows
    // desktop implementation (confirmed: absent from `windows/flutter/
    // generated_plugin_registrant.cc`, unlike `firebase_auth`/
    // `cloud_firestore`, which are present there) — both
    // `onMessageOpenedApp` and `getInitialMessage()` go through platform
    // channels with no handler registered on that platform, throwing the
    // same class of `Unable to establish connection on channel` failure
    // this session's own `[AUTH-TRACE]` investigation found for
    // `cloud_functions` on Windows. A missed notification tap is the
    // correct, disclosed degradation there (mirrors
    // `FcmRegistrationService`'s own "best-effort, never disrupt the app"
    // precedent) — never a startup crash.
    final messagingSupported =
        kIsWeb || defaultTargetPlatform != TargetPlatform.windows;
    if (messagingSupported) {
      _staffSessionSubscription = ref.listenManual<ActorSession?>(
        actorSessionProvider,
        (previous, next) => _maybeRegisterStaffDevice(next),
      );
      _maybeRegisterStaffDevice(ref.read(actorSessionProvider));
      final staffPush = ref.read(staffPushNotificationsProvider);
      staffPush.initialize(_openRoute);
      _foregroundMessageSubscription =
          FirebaseMessaging.onMessage.listen(staffPush.showForeground);
      // A push tapped while the app was already running.
      _notificationTapSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
      // A push tapped while the app was fully terminated — the message that
      // actually launched this run.
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) _handleNotificationTap(message);
      });
    }
  }

  void _maybeRegisterDeviceToken(AuthState authState) {
    if (_registeredThisSession) return;
    if (!isRealCustomer(authState)) return;
    final uid = authState.session!.uid;
    _registeredThisSession = true;
    ref.read(fcmRegistrationServiceProvider).registerForUid(uid: uid);
  }

  void _maybeRegisterStaffDevice(ActorSession? session) {
    if (session == null || !session.isValid) return;
    if (_registeredStaffUid == session.actorId) return;
    _registeredStaffUid = session.actorId;
    ref.read(fcmRegistrationServiceProvider).registerForUid(
          uid: session.actorId,
        );
  }

  void _handleNotificationTap(RemoteMessage message) =>
      _openRoute(message.data);

  void _openRoute(Map<String, dynamic> data) {
    final route = CourierPushTapRouter.handles(data)
        ? CourierPushTapRouter.resolveRoute(data)
        : ReservationNotificationTapRouter.resolveRoute(data);
    if (route == null) return;
    ref.read(appRouterProvider).go(route);
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _staffSessionSubscription?.close();
    _authSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 8 (`docs/decisions.md` ADR-025): `resolvedAppThemeProvider`
    // falls back to the unmodified `AppTheme.lightTheme` while
    // loading/on error/when no tenant brand theme exists yet — today's
    // single-tenant appearance is unaffected until a tenant owner
    // actually sets one.
    final theme = ref.watch(resolvedAppThemeProvider).when(
          data: (theme) => theme,
          loading: () => AppTheme.lightTheme,
          error: (_, __) => AppTheme.lightTheme,
        );
    return MaterialApp.router(
      title: 'Abaküs One',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
