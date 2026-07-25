import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/profile_model.dart';

class ProfileNotifier extends Notifier<ProfileModel> {
  @override
  ProfileModel build() {
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
