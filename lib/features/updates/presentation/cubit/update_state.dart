enum UpdateStatus { initial, checking, downloading, success, error }

class UpdateState {
  final UpdateStatus status;
  final double progress; // 0.0 to 1.0
  final int bytesReceived;
  final int totalBytes;
  final String? downloadedFilePath;
  final String? errorMessage;
  final String updateUrl;
  final String currentVersion;
  final String? latestVersion;
  final bool isCheckingVersion;
  final bool isUpToDate;
  final String? releaseNotes;
  final String statusMessage;

  const UpdateState({
    this.status = UpdateStatus.initial,
    this.progress = 0.0,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.downloadedFilePath,
    this.errorMessage,
    this.updateUrl = 'https://panel.ragnargroup.app/updates/app-release.apk',
    this.currentVersion = '1.0.0+6',
    this.latestVersion,
    this.isCheckingVersion = false,
    this.isUpToDate = false,
    this.releaseNotes,
    this.statusMessage = 'Listo para buscar actualizaciones',
  });

  UpdateState copyWith({
    UpdateStatus? status,
    double? progress,
    int? bytesReceived,
    int? totalBytes,
    String? downloadedFilePath,
    String? errorMessage,
    String? updateUrl,
    String? currentVersion,
    String? latestVersion,
    bool? isCheckingVersion,
    bool? isUpToDate,
    String? releaseNotes,
    String? statusMessage,
  }) {
    return UpdateState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedFilePath: downloadedFilePath ?? this.downloadedFilePath,
      errorMessage: errorMessage,
      updateUrl: updateUrl ?? this.updateUrl,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      isCheckingVersion: isCheckingVersion ?? this.isCheckingVersion,
      isUpToDate: isUpToDate ?? this.isUpToDate,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
