import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/backups/data/models/backup_models.dart';
import 'package:moly_ide/features/backups/presentation/cubit/backups_state.dart';

class BackupsCubit extends Cubit<BackupsState> {
  final OrchestratorApiClient apiClient;

  BackupsCubit({required this.apiClient}) : super(const BackupsState());

  Future<void> loadBackups() async {
    emit(state.copyWith(status: BackupsStatus.loading));
    try {
      final resp = await apiClient.dio.get('/backups');
      final model = BackupsOverviewModel.fromJson(resp.data);
      emit(state.copyWith(status: BackupsStatus.success, overview: model));
    } catch (e) {
      emit(state.copyWith(status: BackupsStatus.failure, errorMessage: 'Error cargando backups: $e'));
    }
  }
}
