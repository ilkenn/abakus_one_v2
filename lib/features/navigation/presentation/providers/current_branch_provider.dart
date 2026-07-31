import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The branch the currently active session operates against — Sprint 5E.
/// **A placeholder, not real branch selection**: this app has no
/// multi-branch switching UI anywhere yet (no screen lets an actor pick
/// which branch they're viewing), so this always resolves to a single
/// fixed branch id. Every courier/CRM/feedback screen this sprint wires
/// into navigation already reads `branchId` as an explicit parameter —
/// this provider exists only so `OperationsHubScreen` has one real,
/// documented source to read it from instead of a scattered literal.
/// Building real branch selection is separate, unrelated feature work.
final currentBranchIdProvider = Provider<String>((ref) => 'branch-1');
