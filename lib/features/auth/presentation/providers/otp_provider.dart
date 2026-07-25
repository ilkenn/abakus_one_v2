import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/otp_challenge.dart';
import 'auth_provider.dart';

/// Purely the OTP screen's own ephemeral UI state — the entered code, the
/// resend cooldown countdown, and the last screen-level error to show.
/// Whether a code is actually correct or expired is decided by
/// `AuthRepository`, never here — this notifier only reflects that result.
class OtpState {
  final String enteredCode;
  final int cooldownSeconds;
  final String? screenError;
  final bool isSubmitting;

  const OtpState({
    this.enteredCode = '',
    this.cooldownSeconds = 0,
    this.screenError,
    this.isSubmitting = false,
  });

  OtpState copyWith({
    String? enteredCode,
    int? cooldownSeconds,
    String? screenError,
    bool clearScreenError = false,
    bool? isSubmitting,
  }) {
    return OtpState(
      enteredCode: enteredCode ?? this.enteredCode,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      screenError: clearScreenError ? null : (screenError ?? this.screenError),
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

/// Scoped to the OTP screen's own lifetime via `.autoDispose` — this
/// provider previously stayed alive for the whole app process, which meant
/// a second visit to the OTP screen (e.g. after going back and requesting
/// a code for a different phone number) reused the first visit's stale
/// `enteredCode`/`cooldownSeconds`/`screenError`, and its cooldown `Timer`
/// kept firing for up to [DevelopmentLocalAuthRepository.resendCooldown]
/// after the screen was gone. `.autoDispose` means a fresh screen visit
/// always gets a fresh `OtpNotifier` (clean state, cooldown read anew from
/// the repository's current configuration) and the old one — including its
/// timer, cancelled via `ref.onDispose` below — is torn down as soon as
/// nothing is watching it anymore.
class OtpNotifier extends AutoDisposeNotifier<OtpState> {
  Timer? _cooldownTimer;

  /// Riverpod 2.6.1's `Ref` doesn't expose a `mounted` getter (added in a
  /// later version this project isn't on — upgrading the package is out of
  /// this fix's scope), so disposal is tracked by hand via this flag,
  /// exactly mirroring what `ref.mounted` would report. Set once, in the
  /// same `ref.onDispose` callback that cancels the cooldown timer.
  bool _disposed = false;

  @override
  OtpState build() {
    ref.onDispose(() {
      _cooldownTimer?.cancel();
      _disposed = true;
    });
    final cooldownSeconds =
        ref.read(authRepositoryProvider).resendCooldownDuration.inSeconds;
    _armCooldown(cooldownSeconds);
    return OtpState(cooldownSeconds: cooldownSeconds);
  }

  void _armCooldown(int seconds) {
    _cooldownTimer?.cancel();
    if (seconds <= 0) return;
    _cooldownTimer = Timer(const Duration(seconds: 1), () {
      final remaining = state.cooldownSeconds - 1;
      state = state.copyWith(cooldownSeconds: remaining < 0 ? 0 : remaining);
      if (remaining > 0) _armCooldown(remaining);
    });
  }

  void updateEnteredCode(String value) {
    state = state.copyWith(enteredCode: value, clearScreenError: true);
  }

  Future<OtpVerificationResult?> submit() async {
    if (state.enteredCode.length != 6) {
      state = state.copyWith(screenError: '6 haneli kodu eksiksiz girin.');
      return null;
    }

    state = state.copyWith(isSubmitting: true, clearScreenError: true);
    final result = await ref.read(authProvider.notifier).verifyOtp(
          state.enteredCode,
        );
    // The screen (and therefore this provider, being `.autoDispose`) may
    // have been torn down while `verifyOtp` was in flight — e.g. the user
    // backed out mid-verification. `AuthNotifier.verifyOtp` already
    // committed any resulting session/auth state regardless, so there's
    // nothing to undo here; this guard only prevents writing to `state`
    // on a disposed notifier, which would throw.
    if (_disposed) return null;
    state = state.copyWith(isSubmitting: false);

    switch (result) {
      case OtpVerificationResult.success:
        break;
      case OtpVerificationResult.invalidCode:
        state = state.copyWith(
          screenError: 'Girdiğiniz kod hatalı. Lütfen tekrar deneyin.',
        );
      case OtpVerificationResult.expired:
        state = state.copyWith(
          screenError: 'Kodun süresi doldu. Lütfen yeni bir kod isteyin.',
        );
    }
    return result;
  }

  Future<void> resend() async {
    if (state.cooldownSeconds > 0) return;

    final sent = await ref.read(authProvider.notifier).resendOtp();
    if (_disposed) return;
    if (sent) {
      final cooldownSeconds =
          ref.read(authRepositoryProvider).resendCooldownDuration.inSeconds;
      state = state.copyWith(
        enteredCode: '',
        clearScreenError: true,
        cooldownSeconds: cooldownSeconds,
      );
      _armCooldown(cooldownSeconds);
    } else {
      state = state.copyWith(
        screenError: ref.read(authProvider).error,
      );
    }
  }
}

final otpProvider = NotifierProvider.autoDispose<OtpNotifier, OtpState>(() {
  return OtpNotifier();
});
