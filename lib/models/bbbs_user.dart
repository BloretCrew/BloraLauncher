class BbbsUser {
  final String username;
  final String? avatar;
  final String? email;
  final List<String> tags;
  final BbbsUserSettings settings;
  final String? title;
  final List<dynamic> labels;
  final bool isSuperAdmin;

  BbbsUser({
    required this.username,
    this.avatar,
    this.email,
    required this.tags,
    required this.settings,
    this.title,
    required this.labels,
    required this.isSuperAdmin,
  });

  factory BbbsUser.fromJson(Map<String, dynamic> json) {
    return BbbsUser(
      username: json['username'] ?? '',
      avatar: json['avatar'],
      email: json['email'],
      tags: List<String>.from(json['tags'] ?? []),
      settings: BbbsUserSettings.fromJson(json['settings'] ?? {}),
      title: json['title'],
      labels: List<dynamic>.from(json['labels'] ?? []),
      isSuperAdmin: json['isSuperAdmin'] ?? false,
    );
  }
}

class BbbsUserSettings {
  final String darkModeSetting;

  BbbsUserSettings({required this.darkModeSetting});

  factory BbbsUserSettings.fromJson(Map<String, dynamic> json) {
    return BbbsUserSettings(
      darkModeSetting: json['darkModeSetting'] ?? 'auto',
    );
  }
}
