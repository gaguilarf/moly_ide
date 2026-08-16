import 'dart:async';
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

    emit(
      state.copyWith(
        chunksPorTarea: mapa,
        // Si no se está mirando nada, la tarea que habla se pone delante: al
        // lanzar desde el detalle de un ticket, la conversación aparece sola.
        conversacionAbierta: state.conversacionAbierta ?? taskId,
      ),
    );
  }

  /// Cambia la conversación que se está mirando (la lista del botón flotante).
  void abrirConversacion(String taskId) =>
      emit(state.copyWith(conversacionAbierta: taskId));

  Future<void> loadDashboardData() async {
    emit(state.copyWith(status: ClaudeStateStatus.loading));
    try {
      final accountsResp = await apiClient.dio.get('/claude/accounts');
      final accounts = (accountsResp.data as List)
          .map((a) => ClaudeAccountModel.fromJson(a))
          .toList();

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

      emit(
        state.copyWith(
          status: ClaudeStateStatus.success,
          accounts: accounts,
          tasks: tasks,
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

  Future<void> respondToHardStop(String response) async {
    final active = state.activeTask;
    if (active == null) return;

    try {
      await apiClient.dio.post(
        '/claude/tasks/${active.id}/respond-hard-stop',
        data: {'response': response},
      );
      _acumular(active.id, '\n[Tú]: $response\n');
      emit(state.copyWith(clearQuestion: true));
    } catch (e) {
      emit(
        state.copyWith(errorMessage: 'Error enviando respuesta a Claude: $e'),
      );
    }
  }

  Future<void> resetAccountQuota(int accountId) async {
    try {
      await apiClient.dio.post('/claude/accounts/$accountId/reset-quota');
      await loadDashboardData();
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error reseteando cuota: $e'));
    }
  }

  @override
  Future<void> close() {
    _wsSubscription?.cancel();
    return super.close();
  }
}
