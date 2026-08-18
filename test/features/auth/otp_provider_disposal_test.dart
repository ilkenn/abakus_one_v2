import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:abakus_one_v2/core/router/app_routes.dart';
import 'package:abakus_one_v2/features/auth/data/repositories/development_local_auth_repository.dart';
import 'package:abakus_one_v2/features/auth/data/session_storage.dart';
import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/otp_provider.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/login_screen.dart';
import 'package:abakus_one_v2/features/auth/presentation/screens/otp_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/screens/main_navigation_screen.dart';

/// Regression tests for the `otpProvider` `.autoDispose` fix — a screen
/// left behind used to leave its `OtpNotifier` (and cooldown `Timer`)
/// alive for the rest of the app process, and a second visit reused its
/// stale `enteredCode`/`cooldownSeconds`/`screenError` instead of starting
/// fresh. See `otp_provider.dart`'s class doc for the full description.
///
/// Note on timing: `testWidgets` runs inside a fake-time zone that only
/// advances when `tester.pump(duration)` runs — a bare `await` on a call
/// that internally does `Future.delayed` (like `AuthRepository.requestOtp`/
/// `verifyOtp`, both of which simulate ~600ms of network latency) never
/// resolves if nothing is pumping yet. Every direct (non-UI-driven)
/// repository call below is therefore fired with `unawaited` immediately
/// followed by a `tester.pump` long enough to carry it to completion,
/// rather than awaited directly.
class _FakeSessionStorage implements SessionStorage {
  AuthSession? stored;

  @override
  Future<AuthSession?> readSession() async => stored;

  @override
  Future<void> writeSession(AuthSession session) async {
    stored = session;
  }

  @override
  Future<void> clearSession() async {
    stored = null;
  }
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          DevelopmentLocalAuthRepository(sessionStorage: _FakeSessionStorage()),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpBlank(WidgetTester tester) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
  }

  Future<void> pumpOtpScreen(WidgetTester tester) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OtpScreen()),
      ),
    );
  }

  /// Starts a real OTP request without blocking on its simulated network
  /// delay, then pumps enough fake time for it to actually complete — see
  /// the file-level note above.
  Future<void> requestOtpAndWait(
      WidgetTester tester, String phoneNumber) async {
    unawaited(container.read(authProvider.notifier).requestOtp(phoneNumber));
    await tester.pump(const Duration(milliseconds: 700));
  }

  /// `flutter_test` fails a test that ends with *any* pending `Timer`,
  /// including one belonging to a still-mounted (not necessarily buggy)
  /// cooldown countdown, or to a throwaway instance a bare `.read()` just
  /// built. Rather than chase the exact number of pumps Riverpod's
  /// disposal scheduler needs, this just lets any active cooldown chain
  /// run all the way to 0 — `_armCooldown` stops rescheduling once it
  /// hits 0 — so no test ends with a dangling `Timer` regardless of
  /// mount/disposal timing.
  Future<void> settleAnyCooldown(WidgetTester tester) {
    return tester.pump(
      DevelopmentLocalAuthRepository.resendCooldown +
          const Duration(seconds: 1),
    );
  }

  testWidgets(
    'OTP ekrani dispose edilince otpProvider dispose edilir '
    '(yeniden okundugunda farkli bir instance doner)',
    (tester) async {
      await requestOtpAndWait(tester, '5321234567');
      await pumpOtpScreen(tester);
      await tester.pump();
      final firstInstance = container.read(otpProvider.notifier);

      // Ekrani kaldir: son watcher kalkar, autoDispose tetiklenir.
      await pumpBlank(tester);
      await tester.pump();

      final secondInstance = container.read(otpProvider.notifier);
      expect(identical(firstInstance, secondInstance), isFalse);

      // This bare `.read()` itself just built a third, throwaway instance
      // (nothing is watching it either) — let its cooldown run out so the
      // test doesn't end with a pending Timer.
      await settleAnyCooldown(tester);
    },
  );

  testWidgets(
    'aktif cooldown Timer dispose sonrasi exception firlatmadan durur',
    (tester) async {
      await requestOtpAndWait(tester, '5321234567');
      await pumpOtpScreen(tester);
      await tester.pump();

      // Timer'in gercekten calistigini dogrula.
      await tester.pump(const Duration(seconds: 2));
      expect(container.read(otpProvider).cooldownSeconds, lessThan(30));

      // Ekrani kaldirarak dispose et, sonra zamani ilerlet: eski Timer
      // iptal edilmediyse artik disposed olan Notifier uzerinde state
      // atamaya calisip exception firlatirdi - pump bunu yakalayip
      // yeniden firlatir.
      await pumpBlank(tester);
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ilk ekranda girilen kod, ekran kapatilip yeniden acildiginda temizdir',
    (tester) async {
      await requestOtpAndWait(tester, '5321234567');
      await pumpOtpScreen(tester);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '999999');
      expect(container.read(otpProvider).enteredCode, '999999');

      await pumpBlank(tester);
      await tester.pump();

      // Farkli bir OTP talebiyle yeni bir OtpScreen'e "gidiliyormus" gibi
      // yeniden ac.
      await pumpOtpScreen(tester);
      await tester.pump();

      expect(container.read(otpProvider).enteredCode, isEmpty);
      expect(find.text('999999'), findsNothing);

      await settleAnyCooldown(tester);
    },
  );

  testWidgets(
    'ilk ekrandaki hata mesaji yeni OTP ekranina tasinmaz',
    (tester) async {
      await requestOtpAndWait(tester, '5321234567');
      await pumpOtpScreen(tester);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Doğrula'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(container.read(otpProvider).screenError, isNotNull);

      await pumpBlank(tester);
      await tester.pump();
      await pumpOtpScreen(tester);
      await tester.pump();

      expect(container.read(otpProvider).screenError, isNull);
      expect(
        find.text('Girdiğiniz kod hatalı. Lütfen tekrar deneyin.'),
        findsNothing,
      );

      await settleAnyCooldown(tester);
    },
  );

  testWidgets(
    'farkli telefon numarasiyla yeni OTP isteginde eski cooldown/state '
    'kullanilmaz',
    (tester) async {
      await requestOtpAndWait(tester, '5321234567');
      await pumpOtpScreen(tester);
      await tester.pump();

      // Ilk numaranin cooldown'unu bir miktar azalt.
      await tester.pump(const Duration(seconds: 5));
      final firstCooldown = container.read(otpProvider).cooldownSeconds;
      expect(firstCooldown, lessThan(30));

      // Ekrani kapat, Login'e don, FARKLI bir numarayla yeni istek gonder.
      await pumpBlank(tester);
      await tester.pump();
      await requestOtpAndWait(tester, '5339876543');

      await pumpOtpScreen(tester);
      await tester.pump();

      // Yeni ekran, eski (azalmis) degeri degil, repository'nin guncel
      // cooldown suresini (30) yansitmali.
      expect(
        container.read(otpProvider).cooldownSeconds,
        DevelopmentLocalAuthRepository.resendCooldown.inSeconds,
      );

      await settleAnyCooldown(tester);
    },
  );

  testWidgets(
    'submit() calisirken ekran/provider dispose olursa exception '
    'olusmaz, navigasyon veya state guncellemesi yapilmaz',
    (tester) async {
      await requestOtpAndWait(tester, '5321234567');
      await pumpOtpScreen(tester);
      await tester.pump();

      await tester.enterText(
        find.byType(TextField),
        DevelopmentLocalAuthRepository.developmentOtpCode,
      );
      // submit() repository'nin ~600ms'lik gecikmesi icinde baslatilir...
      await tester.tap(find.text('Doğrula'));
      await tester.pump(const Duration(milliseconds: 100));

      // ...ama gecikme bitmeden ekran (ve dolayisiyla otpProvider) kaldirilir.
      await pumpBlank(tester);

      // Repository'nin gecikmesinin geri kalanini ve sonrasini ilerlet.
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);
      expect(find.byType(MainNavigationScreen), findsNothing);
      expect(find.byType(OtpScreen), findsNothing);

      await settleAnyCooldown(tester);
    },
  );

  testWidgets(
    'resend() calisirken ekran/provider dispose olursa exception olusmaz',
    (tester) async {
      await requestOtpAndWait(tester, '5321234567');
      await pumpOtpScreen(tester);
      await tester.pump();

      // Cooldown'un bitmesini bekle ki resend butonu aktif olsun.
      await tester.pump(
        DevelopmentLocalAuthRepository.resendCooldown +
            const Duration(seconds: 1),
      );

      // resend() repository'nin ~600ms'lik gecikmesi icinde baslatilir...
      await tester.tap(find.text('Kodu yeniden gönder'));
      await tester.pump(const Duration(milliseconds: 100));

      // ...ama gecikme bitmeden ekran kaldirilir.
      await pumpBlank(tester);
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);

      await settleAnyCooldown(tester);
    },
  );

  group('mevcut davranislar (regresyon)', () {
    /// [LoginScreen] and [OtpScreen] now navigate via `go_router`
    /// (`context.push`/`context.go`), so this group needs a `GoRouter`
    /// ancestor rather than the bare `MaterialApp(home: ...)` it used
    /// pre-P1-010 — unlike this file's other groups, which reach
    /// `OtpScreen` directly and never hit a code path that navigates.
    GoRouter testRouter() {
      return GoRouter(
        initialLocation: AppRoutes.login,
        routes: [
          GoRoute(
            path: AppRoutes.login,
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: AppRoutes.otp,
            builder: (context, state) => const OtpScreen(),
          ),
          GoRoute(
            path: AppRoutes.main,
            builder: (context, state) => const MainNavigationScreen(),
          ),
        ],
      );
    }

    Future<void> pumpFromLogin(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: testRouter()),
        ),
      );
      await tester.pumpAndSettle();
      // .first — LoginScreen's phone field is first; "Geliştirici Girişi"
      // (TEMPORARY_DEVELOPER_LOGIN) may render 2 more when DEV_LOGIN_PIN
      // is configured at test time.
      await tester.enterText(find.byType(TextFormField).first, '5321234567');
      await tester.tap(find.text('Devam Et'));
      await tester.pumpAndSettle();
    }

    testWidgets('dogru kod ile OTP basarisi MainNavigationScreen\'e gecer', (
      tester,
    ) async {
      await pumpFromLogin(tester);

      await tester.enterText(
        find.byType(TextField),
        DevelopmentLocalAuthRepository.developmentOtpCode,
      );
      await tester.tap(find.text('Doğrula'));
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationScreen), findsOneWidget);

      await settleAnyCooldown(tester);
    });

    testWidgets('yanlis kod hata mesaji gosterir', (tester) async {
      await pumpFromLogin(tester);

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Doğrula'));
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        find.text('Girdiğiniz kod hatalı. Lütfen tekrar deneyin.'),
        findsOneWidget,
      );

      await settleAnyCooldown(tester);
    });

    testWidgets('cooldown bitmeden yeniden gonder pasiftir', (tester) async {
      await pumpFromLogin(tester);

      expect(find.textContaining('Yeniden gönder ('), findsOneWidget);

      await settleAnyCooldown(tester);
    });

    testWidgets(
      'cooldown bitince yeniden gonder butonu aktif olur ve guvenle calisir',
      (tester) async {
        await pumpFromLogin(tester);

        await settleAnyCooldown(tester);
        expect(find.text('Kodu yeniden gönder'), findsOneWidget);

        await tester.tap(find.text('Kodu yeniden gönder'));
        await tester.pump(const Duration(milliseconds: 700));

        // The repository's own cooldown guard uses real wall-clock time
        // (`DateTime.now()`), which `tester.pump`'s fake clock cannot
        // advance - within this fast-running test almost no real time has
        // passed, so this second request legitimately still hits the
        // repository's cooldown check, exactly as a real second tap this
        // soon after the first would. What this asserts is that pressing
        // the button once the screen-level cooldown reaches zero is always
        // handled safely: no exception, and a coherent screen error rather
        // than a silent no-op.
        expect(tester.takeException(), isNull);
        expect(container.read(otpProvider).screenError, isNotNull);

        await settleAnyCooldown(tester);
      },
    );
  });
}
