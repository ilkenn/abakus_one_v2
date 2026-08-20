import 'dart:async';

import '../../../bootstrap/app_environment.dart';
import '../../../core/services/logging/log_level.dart';
import '../../../core/services/logging/logging_service.dart';

/// Profile P.4.3A — Storage Upload Control-Flow Diagnostic (2026-08-19).
///
/// A physical-device test confirmed the Storage Emulator IS reachable
/// (`adb reverse tcp:9199`, a port probe both returning success) yet
/// `finalizeCustomerPhotoUpload` never fires and no failure diagnostic
/// appears — meaning the stall is somewhere in the Flutter control flow
/// between a successful upload-grant response and the backend's finalize
/// trigger, not in emulator routing (already exhaustively audited/ruled
/// out — see the "Physical Storage Upload Failure Diagnostic" section of
/// `docs/decisions.md`). [logUploadMilestone] gives that control flow a
/// breadcrumb trail so the exact stage a future physical-device run stalls
/// at is directly observable, instead of inferred from silence.
///
/// DEVELOPMENT-ONLY (silently a no-op otherwise, mirroring every other
/// diagnostic in this feature). **Never logs**: image bytes, auth tokens,
/// App Check tokens, or upload-grant secrets beyond the already-opaque
/// `objectPath`/`grantId` this feature already treats as safe to log.
void logUploadMilestone(
  LoggingService loggingService,
  String milestone, [
  Map<String, Object?> context = const {},
]) {
  if (AppEnvironment.current != AppEnvironment.development) return;
  loggingService.log(
    LogLevel.debug,
    '[CustomerPhotoUpload] $milestone',
    context: context,
  );
}

/// Races [future] against a [threshold] timer purely to log a "still
/// pending" breadcrumb if [future] hasn't resolved by then — it never
/// cancels, truncates, or otherwise alters [future]'s own outcome, so
/// this cannot change what the real upload does, only what gets logged
/// about it. Answers, without physical-device access, the specific
/// question this diagnostic exists to answer: was a given async step
/// actually invoked and is it still genuinely in flight (a slow but
/// working network call), or did it never start / never return at all
/// (a real hang)?
///
/// DEVELOPMENT-ONLY; a no-op passthrough in every other environment.
Future<T> withUploadHangDiagnostic<T>(
  LoggingService loggingService,
  String label,
  Future<T> future, {
  Duration threshold = const Duration(seconds: 20),
}) {
  if (AppEnvironment.current != AppEnvironment.development) return future;

  var completed = false;
  final timer = Timer(threshold, () {
    if (completed) return;
    logUploadMilestone(
      loggingService,
      '$label — still pending after ${threshold.inSeconds}s (possible hang)',
    );
  });

  return future.whenComplete(() {
    completed = true;
    timer.cancel();
  });
}
