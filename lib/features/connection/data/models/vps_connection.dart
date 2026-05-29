class VPSConnection {
  final String host;
  final String port;
  final String username;
  final String password;

  VPSConnection({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
      };

  factory VPSConnection.fromJson(Map<String, dynamic> json) => VPSConnection(
        host: json['host'] ?? '',
        port: json['port'] ?? '22',
        username: json['username'] ?? '',
        password: json['password'] ?? '',
      );
}
