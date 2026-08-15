import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bootstrap/firebase_ready_provider.dart';
import 'core/auth/real_customer_check.dart';
import 'core/notifications/fcm_registration_provider.dart';
import 'core/notifications/reservation_notification_tap_router.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/branding/presentation/providers/resolved_app_theme_provider.dart';

class AbakusApp extends ConsumerStatefulWidget {
  const AbakusApp({super.key});

  @override
  ConsumerState<AbakusApp> createState() => _AbakusAppState();
}

class _AbakusAppState extends ConsumerState<AbakusApp> {
  StreamSubscription<RemoteMessage>? _notificationTapSubscription;
  ProviderSubscription<AuthState>? _authSubscription;
  bool _registeredThisSession = false;

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

    // A push tapped while the app was already running.
    _notificationTapSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    // A push tapped while the app was fully terminated — the message that
    // actually launched this run.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleNotificationTap(message);
    });
  }

  void _maybeRegisterDeviceToken(AuthState authState) {
    if (_registeredThisSession) return;
    if (!isRealCustomer(authState)) return;
    final uid = authState.session!.uid;
    _registeredThisSession = true;
    ref.read(fcmRegistrationServiceProvider).registerForUid(uid: uid);
  }

  void _handleNotificationTap(RemoteMessage message) {
    final route = ReservationNotificationTapRouter.resolveRoute(message.data);
    if (route == null) return;
    ref.read(appRouterProvider).go(route);
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
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
