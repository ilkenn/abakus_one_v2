import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/customer_registration_gateway.dart';
import '../../domain/customer_registration_validation.dart';
import '../../domain/models/customer_gender.dart';
import '../../domain/models/occupation_status.dart';
import 'customer_registration_providers.dart';

enum CustomerRegistrationSubmitPhase { idle, submitting, failed }

class CustomerRegistrationSubmitState {
  const CustomerRegistrationSubmitState({
    this.phase = CustomerRegistrationSubmitPhase.idle,
    this.errorMessage,
  });

  final CustomerRegistrationSubmitPhase phase;
  final String? errorMessage;

  bool get isSubmitting => phase == CustomerRegistrationSubmitPhase.submitting;
}

const String _kGenericFailureMessage =
    'Profilin tamamlanamadı. Lütfen tekrar dene.';
const String _kInvalidInputMessage =
    'Girdiğin bilgileri kontrol et ve tekrar dene.';

/// Orchestrates the "Profilini Tamamla" submit action — deliberately does
/// NOT own the form's `TextEditingController`s/field values themselves
/// (those stay screen-local, mirroring `LoginScreen`'s own established
/// pattern), only the async submit lifecycle: idle -> submitting ->
/// idle/failed. Mirrors `CustomerPhotoUploadNotifier`'s exact shape
/// (`AutoDisposeNotifier`, a synchronous busy-phase set before the first
/// `await` to close the double-tap race that feature's own history
/// already found and fixed once).
///
/// **Never navigates itself.** A successful submit leaves this notifier
/// back at `idle`; the actual transition off "Profilini Tamamla" is
/// entirely router-driven, via `customerProfileCompletionStateProvider`
/// re-resolving and `AppRouteGuard` redirecting once that state flips to
/// `complete`.
///
/// **CR.1.2 (2026-08-20) — the completion-state refresh is deliberately
/// NOT part of [submit] any more.** [submit] now only performs Step 1 of
/// the two-step onboarding flow (the mandatory form) — server truth is
/// already fully committed the moment it returns `true` (`completeCustomerProfile`
/// already created/repaired the canonical customer + tenant membership),
/// but the screen must stay on `/complete-profile` long enough to offer
/// the OPTIONAL Step 2 photo. Invalidating `customerProfileCompletionResultProvider`
/// here, as CR.1's original security fix did, would immediately flip
/// `customerProfileCompletionStateProvider` to `complete` and let the
/// router's reactive redirect yank the customer to `/main` mid-Step-2. The
/// explicit refresh now lives in [finishOnboarding], called only once Step
/// 2 itself finishes or is skipped — never a second completion flag, never
/// a router change: the resolver already correctly returns `complete` from
/// Step 1 alone if queried fresh (e.g. an app restart between steps), this
/// is purely about not proactively triggering that query too early.
class CustomerRegistrationSubmitNotifier
    extends AutoDisposeNotifier<CustomerRegistrationSubmitState> {
  @override
  CustomerRegistrationSubmitState build() {
    return const CustomerRegistrationSubmitState();
  }

  Future<bool> submit({
    required String firstName,
    required String lastName,
    required String email,
    required OccupationStatus occupationStatus,
    String? workplaceName,
    String? educationalInstitutionName,
    required CustomerGender gender,
    required DateTime birthDate,
  }) async {
    // Duplicate-tap guard — synchronous, before the first `await`, closing
    // the exact race `CustomerPhotoUploadNotifier`'s own history disclosed
    // (two near-simultaneous calls both passing an `isBusy` check that was
    // only set after an `await`).
    if (state.isSubmitting) return false;
    state = const CustomerRegistrationSubmitState(
      phase: CustomerRegistrationSubmitPhase.submitting,
    );

    try {
      await ref
          .read(customerRegistrationGatewayProvider)
          .completeCustomerProfile(
            firstName: firstName,
            lastName: lastName,
            email: normalizeEmail(email),
            occupationStatus: occupationStatus,
            workplaceName: workplaceName,
            educationalInstitutionName: educationalInstitutionName,
            gender: gender,
            birthDate: formatCanonicalBirthDate(birthDate),
          );
      // No completion-state invalidate here — see this class's own doc
      // comment. Step 1 succeeding does not yet end the onboarding UI
      // flow; [finishOnboarding] does that, once Step 2 finishes/is
      // skipped.
      state = const CustomerRegistrationSubmitState();
      return true;
    } on CustomerRegistrationGatewayException catch (error) {
      state = CustomerRegistrationSubmitState(
        phase: CustomerRegistrationSubmitPhase.failed,
        errorMessage: error.code == 'invalid-argument'
            ? _kInvalidInputMessage
            : _kGenericFailureMessage,
      );
      return false;
    }
  }

  /// CR.1.2 — the ONE re-fetch trigger for the server-authoritative
  /// completion state (beyond a natural `authProvider` change), moved out
  /// of [submit] itself so it fires only once the optional Step 2 photo
  /// step has genuinely finished — successfully, skipped
  /// ("Şimdilik Geç"), or deferred after a failed upload
  /// ("Daha Sonra Ekle"). Never polling: a single, deliberate invalidate,
  /// exactly mirroring the discipline the CR.1 security fix originally
  /// established for this same call, just relocated to the correct place
  /// in the now-two-step flow.
  void finishOnboarding() {
    ref.invalidate(customerProfileCompletionResultProvider);
  }

  void dismissError() {
    state = const CustomerRegistrationSubmitState();
  }
}

final customerRegistrationSubmitProvider = NotifierProvider.autoDispose<
    CustomerRegistrationSubmitNotifier, CustomerRegistrationSubmitState>(
  CustomerRegistrationSubmitNotifier.new,
);
