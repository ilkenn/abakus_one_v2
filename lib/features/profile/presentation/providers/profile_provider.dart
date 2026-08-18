import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/models/profile_model.dart';

/// Canonical identity bridge — Sprint 9C (`docs/decisions.md` ADR-026,
/// superseding Sprint 5E's ADR-022 phone-derived-string version).
/// [ProfileModel.id] is now [AuthSession.uid] itself — a real Firebase Auth
/// UID, the same canonical id `features/crm`'s `currentCustomerProvider`
/// keys its `Customer` record by (see `ResolveCurrentCustomer`) — rather
/// than a separately-derived string that merely happened to also start
/// from the phone number. `name`/`email` for a real signed-in user are no
/// longer a hardcoded literal: `name` falls back to the phone number
/// itself (real data, not a fabricated person — the profile screen's own
/// edit flow is where a user sets a real display name); `email` has no
/// real source yet (phone-OTP auth never collects one), so it's an honest
/// empty string rather than a fake address. This deliberately does **not**
/// import `features/crm` to read `Customer.displayName` — the existing
/// `currentCustomerProvider` doc comment already documents auth↔crm as the
/// **one** allowed cross-feature exception (`CLAUDE.md` §3); adding a
/// second one (profile↔crm) is an architecture change out of this
/// sprint's identity-linking scope, not a silent shortcut.
///
/// P.1 (2026-08-19): the guest/signed-out branch no longer returns a
/// hardcoded mock person ("Ahmet Yılmaz" et al) — [build] returns `null`
/// instead. There is no real "guest profile" to show; presenting one as
/// if real was exactly the mock-data risk this redesign was asked to
/// remove. Every consumer must treat `null` as "show a sign-in state,"
/// not paper over it with fabricated identity.
class ProfileNotifier extends Notifier<ProfileModel?> {
  @override
  ProfileModel? build() {
    final session = ref.watch(authProvider).session;
    if (session == null) return null;
    return ProfileModel(
      id: session.uid,
      name: session.phoneNumber,
      email: '',
    );
  }

  void updateProfilePicture(String path) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(profilePicturePath: path);
  }

  void removeProfilePicture() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(removeProfilePicture: true);
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileModel?>(() {
  return ProfileNotifier();
});
