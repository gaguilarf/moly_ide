class AuthUserModel {
  final int id;
  final String email;
  final String name;
  final String role;
  final bool isActive;

  AuthUserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.isActive,
  });

  factory AuthUserModel.fromJson(Map<String, dynamic> json) => AuthUserModel(
        id: json['id'] ?? 0,
        email: json['email'] ?? '',
        name: json['name'] ?? '',
        role: json['role'] ?? 'developer',
        isActive: json['is_active'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'role': role,
        'is_active': isActive,
      };
}
