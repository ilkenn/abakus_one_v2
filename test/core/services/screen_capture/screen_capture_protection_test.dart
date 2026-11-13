import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/core/services/screen_capture/screen_capture_protection.dart';
import 'package:abakus_one_v2/features/admin/presentation/widgets/staff_screen_capture_guard.dart';

class _RecordingChannel implements ScreenCaptureChannel {
  final List<bool> calls = [];

  @override
  Future<void> setProtected(bool protected) async => calls.add(protected);
}

void main() {
  group('ScreenCaptureProtection (ADR-085 stage 2)', () {
    test('protects while at least one staff screen is open', () {
      final channel = _RecordingChannel();
      final protection = ScreenCaptureProtection(channel);

      protection.acquire();
      protection.acquire();
      protection.release();
      expect(protection.isProtected, isTrue);
      protection.release();
      expect(protection.isProtected, isFalse);
      expect(channel.calls, [true, false],
          reason: 'only real changes reach the native side');
    });

    test('the Platform Owner is exempt, and protection returns without them',
        () {
      final channel = _RecordingChannel();
      final protection = ScreenCaptureProtection(channel)..acquire();

      protection.exempt = true;
      expect(protection.isProtected, isFalse);
      protection.exempt = false;
      expect(protection.isProtected, isTrue);
      expect(channel.calls, [true, false, true]);
    });

    test('an extra release never goes below zero', () {
      final protection = ScreenCaptureProtection(_RecordingChannel())
        ..release()
        ..acquire();
      expect(protection.isProtected, isTrue);
    });
  });

  testWidgets('StaffScreenCaptureGuard protects only while it is on screen',
      (tester) async {
    final channel = _RecordingChannel();
    final show = ValueNotifier(true);
    await tester.pumpWidget(ProviderScope(
      overrides: [screenCaptureChannelProvider.overrideWithValue(channel)],
      child: MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, visible, __) => visible
              ? const StaffScreenCaptureGuard(child: Text('POS'))
              : const Text('Giriş'),
        ),
      ),
    ));
    expect(channel.calls, [true]);

    show.value = false;
    await tester.pump();
    expect(channel.calls, [true, false]);
  });
}
