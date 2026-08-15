class PortInfoModel {
  final int port;
  final List<String> addresses;
  final String? process;
  final bool isExposed;
  final String? serviceName;
  final String? environment;
  final String? category;

  PortInfoModel({
    required this.port,
    required this.addresses,
    this.process,
    required this.isExposed,
    this.serviceName,
    this.environment,
    this.category,
  });

  factory PortInfoModel.fromJson(Map<String, dynamic> json) => PortInfoModel(
        port: json['port'] ?? 0,
        addresses: (json['addresses'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        process: json['process'],
        isExposed: json['is_exposed'] ?? false,
        serviceName: json['service_name'],
        environment: json['environment'],
        category: json['category'],
      );
}

class ServerInfrastructureModel {
  final String serverName;
  final String serverHost;
  final bool isReachable;
  final String checkedAt;
  final List<PortInfoModel> ports;

  ServerInfrastructureModel({
    required this.serverName,
    required this.serverHost,
    required this.isReachable,
    required this.checkedAt,
    required this.ports,
  });

  factory ServerInfrastructureModel.fromJson(Map<String, dynamic> json) => ServerInfrastructureModel(
        serverName: json['server_name'] ?? '',
        serverHost: json['server_host'] ?? '',
        isReachable: json['is_reachable'] ?? false,
        checkedAt: json['checked_at'] ?? '',
        ports: (json['ports'] as List<dynamic>?)
                ?.map((e) => PortInfoModel.fromJson(e))
                .toList() ??
            [],
      );
}
