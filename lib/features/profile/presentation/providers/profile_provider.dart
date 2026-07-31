import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/models/profile_model.dart';

/// Sprint 5E identity bridge (`docs/decisions.md` ADR-022): when a real
/// [AuthSession] exists, [ProfileModel.id] is derived deterministically
/// from its phone number — the same real anchor
/// `features/crm`'s `currentCustomerProvider` resolves its `Customer`
/// from — rather than the old hardcoded `'user_123'`. This keeps
/// [ProfileNotifier] synchronous (unlike `currentCustomerProvider`, which
/// must be async to look up/create a `Customer` record) while still
/// linking the two to the same real person via a shared key. Signed-out/
/// guest sessions keep today's mock seed — there is no real identity to
/// derive from yet in that case.
class ProfileNotifier extends Notifier<ProfileModel> {
  @override
  ProfileModel build() {
    final session = ref.watch(authProvider).session;
    if (session != null) {
      return ProfileModel(
        id: 'customer-${session.phoneNumber}',
        name: 'Ahmet Yılmaz',
        email: 'ahmet.yilmaz@abakusbowl.com',
      );
    }
    return const ProfileModel(
      id: 'user_123',
      name: 'Ahmet Yılmaz',
      email: 'ahmet.yilmaz@abakusbowl.com',
    );
  }

  void updateProfilePicture(String path) {
    state = state.copyWith(profilePicturePath: path);
  }

  void removeProfilePicture() {
    state = state.copyWith(removeProfilePicture: true);
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileModel>(() {
  return ProfileNotifier();
});
