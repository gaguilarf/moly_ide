import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/documentation/data/models/doc_models.dart';
import 'package:moly_ide/features/documentation/presentation/cubit/docs_state.dart';

class DocsCubit extends Cubit<DocsState> {
  final OrchestratorApiClient apiClient;

  DocsCubit({required this.apiClient}) : super(const DocsState());

  /// Trae los temas de la documentación viva.
  ///
  /// Antes esto pedía `/docs`, que recorre ficheros `.md` de un directorio del
  /// Jetson. Ese directorio no existe —era `docs_brittanygroup`, ya retirado—,
  /// así que la respuesta era siempre `[]` y la pestaña salía vacía sin decir
  /// por qué.
  Future<void> loadDocuments() async {
    emit(state.copyWith(status: DocsStatus.loading));
    try {
      final resp = await apiClient.dio.get('/documentacion/temas');
      final temas = ((resp.data['temas'] as List?) ?? [])
          .map((t) => TemaDocModel.fromJson(t))
          .toList();

      emit(
        state.copyWith(
          status: DocsStatus.success,
          temas: temas,
          cerrarTema: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: DocsStatus.failure,
          errorMessage: 'No se pudo cargar la documentación: ${_detalle(e)}',
        ),
      );
    }
  }

  Future<void> abrirTema(TemaDocModel tema) async {
    emit(state.copyWith(temaAbierto: tema, cargandoTema: true, secciones: []));
    try {
      final resp = await apiClient.dio.get('/documentacion/temas/${tema.slug}');
      final secciones =
          ((resp.data['secciones'] as List?) ?? [])
              .map((s) => SeccionDocModel.fromJson(s))
              .toList()
            ..sort((a, b) => a.orden.compareTo(b.orden));

      emit(state.copyWith(secciones: secciones, cargandoTema: false));
    } catch (e) {
      emit(
        state.copyWith(
          cargandoTema: false,
          errorMessage: 'No se pudo abrir «${tema.titulo}»: ${_detalle(e)}',
        ),
      );
    }
  }

  void volverALista() => emit(state.copyWith(cerrarTema: true));

  String _detalle(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) return data['detail'];
      if (e.response != null) return 'HTTP ${e.response?.statusCode}';
      return 'sin conexión con el Jetson';
    }
    return e.toString();
  }
}
