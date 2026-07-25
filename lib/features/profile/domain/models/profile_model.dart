class ProfileModel {
  final String id;
  final String name;
  final String email;
  final String? profilePicturePath;

  const ProfileModel({
    required this.id,
    required this.name,
    required this.email,
    this.profilePicturePath,
  });

  ProfileModel copyWith({
    String? id,
    String? name,
    String? email,
    String? profilePicturePath,
    bool removeProfilePicture = false,
  }) {
    return ProfileModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      profilePicturePath: removeProfilePicture
          ? null
          : (profilePicturePath ?? this.profilePicturePath),
    );
  }
}
