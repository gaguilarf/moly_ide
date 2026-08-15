import 'package:moly_ide/features/backups/data/models/backup_models.dart';

enum BackupsStatus { initial, loading, success, failure }

class BackupsState {
  final BackupsStatus status;
  final BackupsOverviewModel? overview;
  final String? errorMessage;

  const BackupsState({
    this.status = BackupsStatus.initial,
    this.overview,
    this.errorMessage,
  });

  BackupsState copyWith({
    BackupsStatus? status,
    BackupsOverviewModel? overview,
    String? errorMessage,
  }) {
    return BackupsState(
      status: status ?? this.status,
      overview: overview ?? this.overview,
      errorMessage: errorMessage,
    );
  }
}
