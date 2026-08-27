import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The branch the currently active session operates against — Sprint 5E,
/// upgraded to real switchable state by AP-2's Admin context switcher
/// (`lib/features/admin/presentation/providers/admin_context_provider.dart`
/// — `AdminContextController`). Defaults to `'branch-1'` (the original
/// Sprint 5E single-branch seed) until the switcher's own auto-select or
/// explicit user choice overwrites it — every existing `ref.watch(
/// currentBranchIdProvider)`/`ref.read(currentBranchIdProvider)` call site
/// across courier/CRM/feedback/restaurant/admin keeps working completely
/// unchanged (a `StateProvider<String>` reads identically to the plain
/// `Provider<String>` this used to be); only code that also reads
/// `.notifier` — the context switcher itself — can change the value.
final currentBranchIdProvider = StateProvider<String>((ref) => 'branch-1');
