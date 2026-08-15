import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/explorer_readonly/data/models/file_models.dart';
import 'package:moly_ide/features/explorer_readonly/presentation/cubit/readonly_explorer_state.dart';

class ReadonlyExplorerCubit extends Cubit<ReadonlyExplorerState> {
  final OrchestratorApiClient apiClient;

  ReadonlyExplorerCubit({required this.apiClient}) : super(const ReadonlyExplorerState());

  Future<void> listDirectory(String path) async {
    emit(state.copyWith(status: ReadonlyExplorerStatus.loading, currentPath: path, clearFile: true));
    try {
      final resp = await apiClient.dio.get('/explorer/tree', queryParameters: {'path': path});
      final files = (resp.data as List).map((f) => RemoteFileItem.fromJson(f)).toList();
      emit(state.copyWith(status: ReadonlyExplorerStatus.success, files: files, currentPath: path));
    } catch (e) {
      emit(state.copyWith(status: ReadonlyExplorerStatus.failure, errorMessage: 'Error listando directorio: $e'));
    }
  }

  Future<void> readConfigFile(String filePath, String fileName) async {
    try {
      final resp = await apiClient.dio.get('/explorer/read-env', queryParameters: {'file_path': filePath});
      final content = resp.data['content']?.toString() ?? '';
      emit(state.copyWith(openFileName: fileName, openFileContent: content));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error leyendo archivo: $e'));
    }
  }

  void navigateUp() {
    final cur = state.currentPath.replaceAll(RegExp(r'/+$'), '');
    final lastSlash = cur.lastIndexOf('/');
    if (lastSlash > 0) {
      listDirectory(cur.substring(0, lastSlash));
    } else if (lastSlash == 0 && cur.length > 1) {
      listDirectory('/');
    }
  }
}
