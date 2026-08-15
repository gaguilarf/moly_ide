import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/documentation/data/models/doc_models.dart';
import 'package:moly_ide/features/documentation/presentation/cubit/docs_state.dart';

class DocsCubit extends Cubit<DocsState> {
  final OrchestratorApiClient apiClient;

  DocsCubit({required this.apiClient}) : super(const DocsState());

  Future<void> loadDocuments() async {
    emit(state.copyWith(status: DocsStatus.loading));
    try {
      final resp = await apiClient.dio.get('/docs');
      final docs = (resp.data as List).map((d) => DocItemModel.fromJson(d)).toList();
      emit(state.copyWith(status: DocsStatus.success, documents: docs));
    } catch (e) {
      emit(state.copyWith(status: DocsStatus.failure, errorMessage: 'Error cargando docs: $e'));
    }
  }

  Future<void> loadDocumentContent(String relPath) async {
    try {
      final resp = await apiClient.dio.get('/docs/content', queryParameters: {'path': relPath});
      final content = resp.data['content']?.toString() ?? '';
      emit(state.copyWith(selectedDocPath: relPath, selectedDocContent: content));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error leyendo documento: $e'));
    }
  }
}
