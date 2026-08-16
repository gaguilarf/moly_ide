import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/core/api/websocket_service.dart';
import 'package:moly_ide/features/claude_agent/data/models/claude_models.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_state.dart';

class ClaudeCubit extends Cubit<ClaudeState> {
  final OrchestratorApiClient apiClient;
  final WebSocketService wsService;
  StreamSubscription<LiveEvent>? _wsSubscription;

  ClaudeCubit({required this.apiClient, required this.wsService})
    : super(const ClaudeState()) {
    _initWebSocketListener();
  }

  void _initWebSocketListener() {
    unawaited(wsService.connect());
    _wsSubscription = wsService.eventsStream.listen((event) {
      switch (event.event) {
        case 'task_log':
          _acumular(
            event.data['task_id']?.toString(),
            event.data['chunk']?.toString() ?? '',
          );
          break;
        case 'hard_stop_triggered':
          final q = event.data['question']?.toString();
          emit(state.copyWith(pendingQuestion: q));
          break;
        case 'hard_stop_resumed':
          emit(state.copyWith(clearQuestion: true));
          break;
        case 'task_started':
        case 'task_finished':
        case 'account_quota_exhausted':
          loadDashboardData();
          break;
      }
    });
  }

  /// Guarda un trozo de salida en la conversación a la que pertenece.
  ///
  /// Un `task_log` sin `task_id` no se puede colocar en ninguna conversación:
  /// se descarta en vez de ensuciar la que esté abierta, que podría ser otra.
  void _acumular(String? taskId, String chunk) {
    if (taskId == null || taskId.isEmpty || chunk.isEmpty) return;

    final mapa = Map<String, List<String>>.from(state.chunksPorTarea);
    mapa[taskId] = [...(mapa[taskId] ?? const []), chunk];

    // Solo se guarda: NO se cambia la conversación que se está mirando. Antes
    // se abría la de la tarea que hablase si no había ninguna abierta, y eso
    // secuestraba la pantalla en blanco del botón «chat nuevo» en cuanto otra
    // tarea escupiera una línea. Quien abre conversación es launchTask, que ya
    // lo hace al crear la tarea.
    emit(state.copyWith(chunksPorTarea: mapa));
  }

  /// Cambia la conversación que se está mirando (la lista del botón flotante).
  void abrirConversacion(String taskId) =>
      emit(state.copyWith(conversacionAbierta: taskId));

  /// Deja de mirar ninguna conversación: la pantalla vuelve en blanco y el
  /// siguiente mensaje abre un chat nuevo. No se crea nada todavía, porque una
  /// tarea sin prompt no tiene sentido en el servidor.
  void nuevaConversacion() => emit(state.copyWith(clearConversacion: true));

  /// Borra una conversación. El servidor se niega con 409 si la tarea sigue
  /// viva, porque su subproceso todavía está escribiendo en la fila.
  Future<String?> borrarConversacion(String taskId) async {
    try {
      await apiClient.dio.delete('/claude/tasks/$taskId');
      _olvidar([taskId]);
      await loadDashboardData();
      return null;
    } catch (e) {
      return _detalle(e);
    }
  }

  /// Borra de golpe las conversaciones ya cerradas (completadas y fallidas).
  Future<String?> borrarTerminadas() async {
    try {
      final terminadas = state.tasks
          .where((t) => !kEstadosEnCurso.contains(t.status))
          .map((t) => t.id)
          .toList();

      await apiClient.dio.delete('/claude/tasks/terminadas');
      _olvidar(terminadas);
      await loadDashboardData();
      return null;
    } catch (e) {
      return _detalle(e);
    }
  }

  /// Quita del estado la salida acumulada de las conversaciones borradas y, si
  /// alguna era la que se estaba mirando, deja de mirarla. Sin esto, la
  /// pantalla seguiría enseñando el contenido de un chat que ya no existe.
  void _olvidar(List<String> ids) {
    final mapa = Map<String, List<String>>.from(state.chunksPorTarea)
      ..removeWhere((id, _) => ids.contains(id));

    emit(
      state.copyWith(
        chunksPorTarea: mapa,
        clearConversacion: ids.contains(state.conversacionAbierta),
      ),
    );
  }

  /// El backend explica en `detail` por qué se niega a borrar.
  String _detalle(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) return data['detail'];
      if (e.response != null) return 'HTTP ${e.response?.statusCode}';
      return 'sin conexión con el Jetson';
    }
    return e.toString();
  }

  Future<void> loadDashboardData() async {
    emit(state.copyWith(status: ClaudeStateStatus.loading));
    try {
      final tasksResp = await apiClient.dio.get('/claude/tasks');
      final tasks = (tasksResp.data as List)
          .map((t) => ClaudeTaskModel.fromJson(t))
          .toList();

      ClaudeTaskModel? active;
      for (final t in tasks) {
        if (t.status == 'ejecutando' ||
            t.status == 'bloqueado_esperando_humano') {
          active = t;
          break;
        }
      }

      // De las tareas que ya no corren, lo guardado es completo: se tira su
      // cola en vivo para que no se cuente dos veces al concatenarla.
      final mapa = Map<String, List<String>>.from(state.chunksPorTarea);
      for (final t in tasks) {
        if (t.status != 'ejecutando') mapa.remove(t.id);
      }

      emit(
        state.copyWith(
          status: ClaudeStateStatus.success,
          tasks: tasks,
          chunksPorTarea: mapa,
          // Sin los `clear*`, cuando ya no hay tarea viva se quedaba la
          // anterior en el estado —y su pregunta— para siempre.
          activeTask: active,
          clearActiveTask: active == null,
          pendingQuestion: active?.pendingQuestion,
          clearQuestion: active?.pendingQuestion == null,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: ClaudeStateStatus.failure,
          errorMessage: 'Error cargando datos de Claude: $e',
        ),
      );
    }
  }

  Future<void> launchTask({
    required String title,
    required String prompt,
    int? ticketId,
    String? targetRepo,
  }) async {
    try {
      final resp = await apiClient.dio.post(
        '/claude/tasks',
        data: {
          'title': title,
          'prompt': prompt,
          'ticket_id': ticketId,
          'target_repo': targetRepo,
        },
      );

      // Se abre la conversación de la tarea recién creada ANTES de recargar:
      // así el prompt que se acaba de escribir ya se ve como mensaje, en vez
      // del «Iniciando tarea...» que antes se quedaba colgado para siempre
      // cuando la tarea moría sin llegar a emitir un solo log.
      final creada = ClaudeTaskModel.fromJson(resp.data);
      emit(state.copyWith(conversacionAbierta: creada.id));

      await loadDashboardData();
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error iniciando tarea: $e'));
    }
  }

  /// Otro turno sobre la MISMA conversación. El servidor retoma la sesión de
  /// Claude, así que recuerda lo anterior.
  ///
  /// Antes cualquier mensaje llamaba a `launchTask`, así que responder a lo que
  /// Claude preguntaba abría un chat nuevo que no sabía nada del anterior.
  Future<String?> continuarConversacion(String taskId, String mensaje) async {
    try {
      await apiClient.dio.post(
        '/claude/tasks/$taskId/continue',
        data: {'response': mensaje},
      );
      await loadDashboardData();
      return null;
    } catch (e) {
      return _detalle(e);
    }
  }

  @override
  Future<void> close() {
    _wsSubscription?.cancel();
    return super.close();
  }
}
