import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/tickets/data/models/ticket_model.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_state.dart';

class TicketsCubit extends Cubit<TicketsState> {
  final OrchestratorApiClient apiClient;

  TicketsCubit({required this.apiClient}) : super(const TicketsState());

  Future<void> loadTickets({String? project}) async {
    emit(state.copyWith(status: TicketsStatus.loading, selectedProject: project));
    try {
      // 1. Cargar proyectos
      final projResp = await apiClient.dio.get('/tickets/projects');
      final projects = (projResp.data as List)
          .map((p) => TicketProjectModel.fromJson(p))
          .toList();

      // 2. Cargar tickets filtrados
      final Map<String, dynamic> params = {};
      if (project != null && project.isNotEmpty) {
        params['project'] = project;
      }
      final ticketsResp = await apiClient.dio.get('/tickets', queryParameters: params);
      final tickets = (ticketsResp.data as List)
          .map((t) => TicketModel.fromJson(t))
          .toList();

      emit(state.copyWith(
        status: TicketsStatus.success,
        projects: projects,
        tickets: tickets,
        selectedProject: project,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: TicketsStatus.failure,
        errorMessage: 'Error cargando tickets: $e',
      ));
    }
  }

  Future<void> createTicket({
    required String projectKey,
    required String title,
    String? description,
    String? plan,
    String type = 'feature',
    String? area,
    String priority = 'media',
  }) async {
    try {
      await apiClient.dio.post('/tickets', data: {
        'project_key': projectKey,
        'title': title,
        'description': description,
        'plan': plan,
        'type': type,
        'area': area,
        'priority': priority,
        'reporter': 'moly_mobile',
      });
      await loadTickets(project: state.selectedProject);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error creando ticket: $e'));
    }
  }

  Future<void> transitionTicket({
    required String code,
    required String toStatus,
    String? note,
  }) async {
    try {
      await apiClient.dio.patch('/tickets/$code/transition', data: {
        'to_status': toStatus,
        'actor': 'moly_mobile',
        'note': note,
      });
      await loadTickets(project: state.selectedProject);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error cambiando estado: $e'));
    }
  }
}
