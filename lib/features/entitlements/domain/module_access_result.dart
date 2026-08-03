import 'module_access_denial_reason.dart';

/// The outcome of `CheckModuleAccess` — Phase 7 (`docs/decisions.md`
/// ADR-024).
class ModuleAccessResult {
  const ModuleAccessResult.granted() : denialReason = null;

  const ModuleAccessResult.denied(this.denialReason);

  final ModuleAccessDenialReason? denialReason;

  bool get isGranted => denialReason == null;
}
