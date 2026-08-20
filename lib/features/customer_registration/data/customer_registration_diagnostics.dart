import '../../../bootstrap/app_environment.dart';
import '../../../core/services/logging/log_level.dart';
import '../../../core/services/logging/logging_service.dart';

/// Customer Registration CR.1 — DEVELOPMENT-ONLY breadcrumb logging for
/// the `completeCustomerProfile` callable boundary, mirroring the exact
/// pattern already established for the Profile Photo upload flow
/// (`lib/features/customer_photos/data/customer_photo_upload_diagnostics.dart`,
/// moved there from `features/profile/` at CR.1.2 once it gained a second
/// feature consumer). Kept as a small, local duplicate here rather than a
/// shared/core promotion — this file's own callable boundary
/// (`completeCustomerProfile`) has exactly one consumer, so nothing about
/// CR.1.2's own extraction applies to it.
///
/// Never logs auth tokens, App Check tokens, or raw form field values —
/// only milestone names and, where included, non-sensitive structural
/// context (booleans, error codes).
void logRegistrationMilestone(
  LoggingService loggingService,
  String milestone, [
  Map<String, Object?> context = const {},
]) {
  if (AppEnvironment.current != AppEnvironment.development) return;
  loggingService.log(
    LogLevel.debug,
    '[CustomerRegistration] $milestone',
    context: context,
  );
}
