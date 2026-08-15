import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/tickets/data/models/ticket_model.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_state.dart';

class TicketsCubit extends Cubit<TicketsState> {
  final OrchestratorApiClient apiClient;

  TicketsCubit({required this.apiClient}) : super(const TicketsState());

  /// Carga proyectos, sprints y los tickets del sprint que toca mostrar.
  ///
  /// Si no hay sprint elegido (o el elegido ya no existe) se cae al sprint
  /// activo, y si no hay ninguno activo al más reciente. Sin esto la petición
  /// salía sin `sprint_id` y el tablero mezclaba los tickets de todos los
  /// sprints: decenas de "hecho" viejos tapando el trabajo en curso.
  Future<void> loadBoard({bool silencioso = false}) async {
    if (!silencioso) {
      emit(state.copyWith(status: TicketsStatus.loading));
    }
    try {
      final projResp = await apiClient.dio.get('/tickets/projects');
      final projects = (projResp.data as List)
          .map((p) => TicketProjectModel.fromJson(p))
          .toList();

      final sprintResp = await apiClient.dio.get('/tickets/sprints');
      final sprints = (sprintResp.data as List)
          .map((s) => SprintModel.fromJson(s))
          .toList();

      final sprintId = _sprintAMostrar(sprints, state.selectedSprintId);
      final tickets = await _fetchTickets(sprintId);

      emit(
        state.copyWith(
          status: TicketsStatus.success,
          projects: projects,
          sprints: sprints,
          tickets: tickets,
          selectedSprintId: sprintId,
          clearSelectedSprint: sprintId == null,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: TicketsStatus.failure,
          errorMessage: 'Error cargando el tablero: ${_detalle(e)}',
        ),
      );
    }
  }

  /// Cambia el sprint visible. Solo recarga tickets: proyectos y sprints ya
  /// están en memoria.
  Future<void> selectSprint(int sprintId) async {
    if (sprintId == state.selectedSprintId) return;
    emit(
      state.copyWith(status: TicketsStatus.loading, selectedSprintId: sprintId),
    );
    try {
      final tickets = await _fetchTickets(sprintId);
      emit(state.copyWith(status: TicketsStatus.success, tickets: tickets));
    } catch (e) {
      emit(
        state.copyWith(
          status: TicketsStatus.failure,
          errorMessage: 'Error cargando el sprint: ${_detalle(e)}',
        ),
      );
    }
  }

  // Los filtros no van al servidor: se aplican sobre los tickets del sprint que
  // ya están cargados (ver TicketsState.visibleTickets).
  void setProjectFilter(String? key) =>
      emit(state.copyWith(projectFilter: key, clearProjectFilter: key == null));

  void setAreaFilter(String? area) =>
      emit(state.copyWith(areaFilter: area, clearAreaFilter: area == null));

  void setPriorityFilter(String? priority) => emit(
    state.copyWith(
      priorityFilter: priority,
      clearPriorityFilter: priority == null,
    ),
  );

  void setQuery(String query) => emit(state.copyWith(query: query));

  void clearFilters() => emit(
    state.copyWith(
      query: '',
      clearProjectFilter: true,
      clearAreaFilter: true,
      clearPriorityFilter: true,
    ),
  );

  /// Cierra el sprint: el backend abre el siguiente y le pasa lo que quedó sin
  /// terminar. Devuelve cuántos tickets se arrastraron, para poder decirlo.
  Future<int?> closeSprint({
    required int sprintId,
    String? nextName,
    String? nextGoal,
    String? nextEndDate,
  }) async {
    try {
      final resp = await apiClient.dio.post(
        '/tickets/sprints/$sprintId/close',
        data: {
          'next_sprint_name': nextName,
          'next_sprint_goal': nextGoal,
          'next_sprint_end_date': nextEndDate,
        },
      );
      final arrastrados = (resp.data['carried_over'] as num?)?.toInt() ?? 0;
      final siguiente = resp.data['next'];
      if (siguiente is Map && siguiente['id'] is int) {
        emit(state.copyWith(selectedSprintId: siguiente['id'] as int));
      }
      await loadBoard(silencioso: true);
      return arrastrados;
    } catch (e) {
      emit(
        state.copyWith(
          errorMessage: _esRutaAusente(e)
              // Mensaje distinto a propósito: un 404 aquí no es un fallo del
              // usuario, es que el Jetson corre una versión del backend sin
              // esta ruta. Sin decirlo, parece que la app está rota.
              ? 'El backend del Jetson todavía no tiene el cierre de sprint: '
                    'falta desplegar backend/app/routers/tickets.py y reiniciar el servicio.'
              : 'No se pudo cerrar el sprint: ${_detalle(e)}',
        ),
      );
      return null;
    }
  }

  Future<void> createSprint({
    required String name,
    String? goal,
    String? endDate,
  }) async {
    try {
      final resp = await apiClient.dio.post(
        '/tickets/sprints',
        data: {
          'name': name,
          'goal': goal,
          'status': 'activo',
          'start_date': DateTime.now().toIso8601String().split('T').first,
          'end_date': endDate,
        },
      );
      final creado = SprintModel.fromJson(resp.data);
      emit(state.copyWith(selectedSprintId: creado.id));
      await loadBoard(silencioso: true);
    } catch (e) {
      emit(
        state.copyWith(
          errorMessage: 'No se pudo crear el sprint: ${_detalle(e)}',
        ),
      );
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
      final resp = await apiClient.dio.post(
        '/tickets',
        data: {
          'project_key': projectKey,
          'title': title,
          'description': description,
          'plan': plan,
          'type': type,
          'area': area,
          'priority': priority,
          'reporter': 'moly_mobile',
        },
      );

      // El backend mete el ticket nuevo en el sprint activo. Si se estaba
      // mirando otro sprint, saltamos al suyo: si no, se crea un ticket que no
      // aparece por ningún lado y parece que la creación falló.
      final creado = TicketModel.fromJson(resp.data);
      if (creado.sprintId != null &&
          creado.sprintId != state.selectedSprintId) {
        emit(state.copyWith(selectedSprintId: creado.sprintId));
      }
      await loadBoard(silencioso: true);
    } catch (e) {
      emit(
        state.copyWith(errorMessage: 'Error creando ticket: ${_detalle(e)}'),
      );
    }
  }

  Future<void> transitionTicket({
    required String code,
    required String toStatus,
    String? note,
  }) async {
    try {
      await apiClient.dio.patch(
        '/tickets/$code/transition',
        data: {'to_status': toStatus, 'actor': 'moly_mobile', 'note': note},
      );
      await loadBoard(silencioso: true);
    } catch (e) {
      emit(state.copyWith(errorMessage: _detalle(e)));
    }
  }

  Future<List<TicketModel>> _fetchTickets(int? sprintId) async {
    final params = <String, dynamic>{};
    if (sprintId != null) params['sprint_id'] = sprintId;
    final resp = await apiClient.dio.get('/tickets', queryParameters: params);
    return (resp.data as List).map((t) => TicketModel.fromJson(t)).toList();
  }

  int? _sprintAMostrar(List<SprintModel> sprints, int? actual) {
    if (sprints.isEmpty) return null;
    if (actual != null && sprints.any((s) => s.id == actual)) return actual;
    for (final s in sprints) {
      if (s.isActivo) return s.id;
    }
    // `/tickets/sprints` llega ordenado por created_at descendente.
    return sprints.first.id;
  }

  bool _esRutaAusente(Object e) =>
      e is DioException && e.response?.statusCode == 404;

  /// El backend explica en `detail` por qué rechaza una transición (409) o exige
  /// nota de cierre (422). Mostrar el `DioException` entero escondía ese texto
  /// tras un volcado de stack.
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
