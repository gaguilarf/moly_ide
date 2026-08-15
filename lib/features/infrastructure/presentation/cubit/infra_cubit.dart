import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/infrastructure/data/models/infra_models.dart';
import 'package:moly_ide/features/infrastructure/presentation/cubit/infra_state.dart';

class InfraCubit extends Cubit<InfraState> {
  final OrchestratorApiClient apiClient;

  InfraCubit({required this.apiClient}) : super(const InfraState());

  Future<void> loadServerStatus({String? node}) async {
    final targetNode = node ?? state.selectedNode;
    emit(state.copyWith(status: InfraStatus.loading, selectedNode: targetNode));
    try {
      final resp = await apiClient.dio.get('/infra/status', queryParameters: {'node': targetNode});
      final model = ServerInfrastructureModel.fromJson(resp.data);
      emit(state.copyWith(status: InfraStatus.success, serverStatus: model, selectedNode: targetNode));
    } catch (e) {
      emit(state.copyWith(status: InfraStatus.failure, errorMessage: 'Error cargando puertos: $e'));
    }
  }
}
