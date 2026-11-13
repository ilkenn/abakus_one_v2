import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ADR-085 stage 2 (KVKK) — the native switch that keeps a window out of
/// screenshots and screen recordings: Android `FLAG_SECURE`, Windows
/// `WDA_EXCLUDEFROMCAPTURE`, iOS a blank cover while the screen is being
/// recorded (iOS cannot block a single screenshot — best effort only).
abstract interface class ScreenCaptureChannel {
  Future<void> setProtected(bool protected);
}

/// The real channel. A platform without a handler (web, macOS, Linux, and
/// every `flutter test` run) simply stays unprotected — never an error.
class MethodChannelScreenCaptureChannel implements ScreenCaptureChannel {
  const MethodChannelScreenCaptureChannel();

  static const _channel = MethodChannel('abakus/screen_capture');

  @override
  Future<void> setProtected(bool protected) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setProtected', protected);
    } on MissingPluginException {
      // No native handler on this platform.
    } on PlatformException {
      // The OS refused (e.g. an old Windows build) — best effort.
    }
  }
}

/// Counts the open screens that hold staff data. The window is protected
/// while at least one is open, unless the signed-in person is exempt (the
/// Platform Owner — wired in `app.dart`). Only real changes reach the
/// native side.
class ScreenCaptureProtection {
  ScreenCaptureProtection(this._channel);

  final ScreenCaptureChannel _channel;
  int _holders = 0;
  bool _exempt = false;
  bool _applied = false;

  bool get isProtected => _holders > 0 && !_exempt;

  void acquire() {
    _holders++;
    _apply();
  }

  void release() {
    if (_holders > 0) _holders--;
    _apply();
  }

  set exempt(bool value) {
    _exempt = value;
    _apply();
  }

  void _apply() {
    final wanted = isProtected;
    if (wanted == _applied) return;
    _applied = wanted;
    unawaited(_channel.setProtected(wanted));
  }
}

final screenCaptureChannelProvider = Provider<ScreenCaptureChannel>(
  (ref) => const MethodChannelScreenCaptureChannel(),
);

final screenCaptureProtectionProvider = Provider<ScreenCaptureProtection>(
  (ref) => ScreenCaptureProtection(ref.watch(screenCaptureChannelProvider)),
);
