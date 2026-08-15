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
          final chunk = event.data['chunk']?.toString() ?? '';
          emit(state.copyWith(liveLogs: [...state.liveLogs, chunk]));
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
          activeTask: active,
          pendingQuestion: active?.pendingQuestion,
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
      emit(state.copyWith(liveLogs: ['[Iniciando tarea en Jetson...]']));
      await apiClient.dio.post(
        '/claude/tasks',
        data: {
          'title': title,
          'prompt': prompt,
          'ticket_id': ticketId,
          'target_repo': targetRepo,
        },
      );
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
      emit(
        state.copyWith(
          clearQuestion: true,
          liveLogs: [...state.liveLogs, '\n[Usuario respondió]: $response\n'],
        ),
      );
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
