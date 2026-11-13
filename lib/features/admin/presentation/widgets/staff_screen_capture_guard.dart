import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/screen_capture/screen_capture_protection.dart';

/// ADR-085 stage 2 (KVKK) — while this is on screen the window stays out of
/// screenshots and recordings. `AdminShellScreen` wraps every signed-in
/// staff surface in it (staff panel, POS, courier); the sign-in screens
/// and the customer app never are. The Platform Owner is exempt through
/// [ScreenCaptureProtection.exempt].
class StaffScreenCaptureGuard extends ConsumerStatefulWidget {
  const StaffScreenCaptureGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StaffScreenCaptureGuard> createState() =>
      _StaffScreenCaptureGuardState();
}

class _StaffScreenCaptureGuardState
    extends ConsumerState<StaffScreenCaptureGuard> {
  // Captured once: `ref` must not be read in dispose().
  late final ScreenCaptureProtection _protection;

  @override
  void initState() {
    super.initState();
    _protection = ref.read(screenCaptureProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _protection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
