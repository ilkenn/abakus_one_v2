import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/real_customer_check.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_registration_gateway.dart';
import '../../domain/models/customer_profile_completion_state.dart';

/// Profile Completion CR.1 — dependency-injection seam for the customer
/// registration/bootstrap feature. Mirrors this codebase's existing
/// gateway-provider convention (e.g. `customerPhotoGatewayProvider`) —
/// deliberately a SEPARATE set of providers from `features/profile/`'s
/// own (never imported from there, never imported into there): this is
/// an authentication/customer-bootstrap boundary, not profile editing
/// (locked architecture decision).
final customerRegistrationGatewayProvider =
    Provider<CustomerRegistrationGateway>((ref) {
  return FirebaseCustomerRegistrationGateway(
    loggingService: ref.watch(loggingServiceProvider),
  );
});

/// Profile Completion CR.1 security fix (2026-08-19) — the server-
/// authoritative resolution of "does this real customer still need
/// Profilini Tamamla," via `getCustomerProfileCompletionState`.
///
/// **Replaced a structurally-broken client-side Firestore probe.** The
/// original design watched `customers/{uid}` and `tenantCustomers
/// /{organizationId}_{uid}` directly via `.snapshots()`. A physical-device
/// run found the exact bug that guaranteed: `tenantCustomers`'
/// `firestore.rules` rule (`allow read: if
/// isOrgMember(resource.data.organizationId)`) only ever grants read
/// access to a **staff** member's `organizationAccess` custom claim — an
/// ordinary phone-verified customer never carries that claim and can
/// never read this collection, for their own record or anyone else's.
/// Every real customer's membership check was therefore guaranteed to
/// fail with `permission-denied`, indistinguishable client-side from "the
/// document genuinely doesn't exist yet" — collapsing a security/backend
/// failure into the same outcome as a legitimate first-time customer.
///
/// The fix moves both reads server-side (Admin SDK, bypasses rules
/// entirely) into one callable that returns a narrow, safe classification
/// — `tenantCustomers`' rule is **unchanged**, still staff-only, still
/// denies every client write. See `getCustomerProfileCompletionState.ts`'s
/// own doc comment for the full reasoning.
///
/// `autoDispose` — only queried while something is actively watching it
/// (the router's `_RouterRefreshListenable`, or the completion screen); a
/// guest/unauthenticated session never calls the gateway at all. No
/// polling: the only re-fetch triggers are an `authProvider` change (a
/// fresh `ref.watch` inside this builder) or an explicit
/// `ref.invalidate(customerProfileCompletionResultProvider)` after a
/// successful `completeCustomerProfile` submit
/// (`customer_registration_submit_provider.dart`) — never a timer, never
/// relying solely on a Firestore snapshot eventually changing.
final customerProfileCompletionResultProvider =
    FutureProvider.autoDispose<CustomerProfileCompletionResult>((ref) {
  final authState = ref.watch(authProvider);
  if (!isRealCustomer(authState)) {
    // Not a real customer session — nothing to gate, and no reason to
    // call the backend on a guest/unauthenticated visitor's behalf. This
    // is what lets AppRouteGuard's own generic "signedIn" branch handle a
    // guest exactly as it already does today.
    return const CustomerProfileCompletionResult(isComplete: true);
  }
  return ref.read(customerRegistrationGatewayProvider).getCompletionState();
});

/// The single source of truth `AppRouteGuard`-adjacent routing logic
/// (`app_router.dart`) and the "Profilini Tamamla" screen both read —
/// reduces [customerProfileCompletionResultProvider]'s `AsyncValue` into
/// the 4-state model routing needs.
///
/// Deliberately a plain, non-`autoDispose` `Provider` — it needs to live
/// for the router's whole lifetime, exactly like `authProvider` itself.
/// It stays alive by continuously watching the `autoDispose` provider
/// above, which is correctly reclaimed once nothing (including this one)
/// watches it any more, e.g. on logout.
final customerProfileCompletionStateProvider =
    Provider<CustomerProfileCompletionState>((ref) {
  final resultAsync = ref.watch(customerProfileCompletionResultProvider);

  // Errors are checked BEFORE the value — an actual backend/callable
  // failure (e.g. a genuine permission or App Check problem) must fail
  // closed as `error`, never be silently treated as `incomplete`.
  if (resultAsync.hasError) {
    return CustomerProfileCompletionState.error(
      resultAsync.error.toString(),
    );
  }

  // `.valueOrNull` — never the unsafe `.value`, which rethrows the
  // underlying error when the state is `AsyncError` with no cached
  // previous value (the same established lesson this codebase's Profile
  // Photo work already disclosed). Already ruled out the error case
  // above, so `null` here means "still loading," not "errored."
  final result = resultAsync.valueOrNull;
  if (result == null) {
    return const CustomerProfileCompletionState.loading();
  }

  return result.isComplete
      ? const CustomerProfileCompletionState.complete()
      : const CustomerProfileCompletionState.incomplete();
});
