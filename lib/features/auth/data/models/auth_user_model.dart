class AuthUserModel {
  final int id;
  final String username;
  final String name;
  final String role;
  final bool isActive;

  AuthUserModel({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    required this.isActive,
  });

  factory AuthUserModel.fromJson(Map<String, dynamic> json) => AuthUserModel(
        id: json['id'] ?? 0,
        username: json['username'] ?? '',
        name: json['name'] ?? '',
        role: json['role'] ?? 'developer',
        isActive: json['is_active'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'role': role,
        'is_active': isActive,
      };
}
