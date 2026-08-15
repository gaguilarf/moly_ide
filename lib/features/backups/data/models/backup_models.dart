class BackupFileModel {
  final String filename;
  final int sizeBytes;
  final String modifiedAt;

  BackupFileModel({
    required this.filename,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  factory BackupFileModel.fromJson(Map<String, dynamic> json) => BackupFileModel(
        filename: json['filename'] ?? '',
        sizeBytes: json['size_bytes'] ?? 0,
        modifiedAt: json['modified_at'] ?? '',
      );
}

class DatabaseBackupModel {
  final String database;
  final BackupFileModel? latestBackup;
  final int totalDumps;
  final bool isHealthy;

  DatabaseBackupModel({
    required this.database,
    this.latestBackup,
    required this.totalDumps,
    required this.isHealthy,
  });

  factory DatabaseBackupModel.fromJson(Map<String, dynamic> json) => DatabaseBackupModel(
        database: json['database'] ?? '',
        latestBackup: json['latest_backup'] != null
            ? BackupFileModel.fromJson(json['latest_backup'])
            : null,
        totalDumps: json['total_dumps'] ?? 0,
        isHealthy: json['is_healthy'] ?? false,
      );
}

class BackupsOverviewModel {
  final String serverName;
  final bool isRunning;
  final String? schedule;
  final List<DatabaseBackupModel> databases;
  final List<String> recentLogs;

  BackupsOverviewModel({
    required this.serverName,
    required this.isRunning,
    this.schedule,
    required this.databases,
    required this.recentLogs,
  });

  factory BackupsOverviewModel.fromJson(Map<String, dynamic> json) => BackupsOverviewModel(
        serverName: json['server_name'] ?? '',
        isRunning: json['is_running'] ?? false,
        schedule: json['schedule'],
        databases: (json['databases'] as List<dynamic>?)
                ?.map((d) => DatabaseBackupModel.fromJson(d))
                .toList() ??
            [],
        recentLogs: (json['recent_logs'] as List<dynamic>?)
                ?.map((l) => l.toString())
                .toList() ??
            [],
      );
}
