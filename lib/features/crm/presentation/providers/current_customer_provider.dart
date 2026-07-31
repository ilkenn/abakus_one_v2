import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../application/use_cases/register_customer.dart';
import '../../application/use_cases/resolve_current_customer.dart';
import '../../domain/segmentation/customer.dart';
import 'crm_dependencies_provider.dart';

/// The signed-in app user's CRM [Customer] record — Sprint 5E's identity
/// bridge (`docs/decisions.md` ADR-022). `null` when signed out, a guest
/// session, or no session exists yet — never a fabricated/default
/// customer.
///
/// **Deliberate, explicitly-reported exception to this codebase's usual
/// "no cross-feature imports" convention** (`CLAUDE.md` §3): resolving
/// "who is the current customer" inherently needs both `features/auth`
/// (the real session) and `features/crm` (the real customer registry) —
/// no third, neutral home for this exists yet, and inventing one would be
/// more scope than "the minimum safe identity bridge" this sprint was
/// asked for. This is the **only** place in the codebase either feature
/// imports the other.
final currentCustomerProvider = FutureProvider<Customer?>((ref) async {
  final authState = ref.watch(authProvider);
  final session = authState.session;
  if (session == null || !authState.isAuthenticated || session.isExpired) {
    return null;
  }

  final resolveCurrentCustomer = ResolveCurrentCustomer(
    repository: ref.watch(customerRepositoryProvider),
    registerCustomer: RegisterCustomer(
      idGenerator: ref.watch(customerIdGeneratorProvider),
      repository: ref.watch(customerRepositoryProvider),
    ),
  );

  return resolveCurrentCustomer(
    phoneNumber: session.phoneNumber,
    displayName: session.phoneNumber,
    now: ref.watch(clockProvider).now(),
  );
});
