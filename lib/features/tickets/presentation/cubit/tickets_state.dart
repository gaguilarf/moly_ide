import 'package:moly_ide/features/tickets/data/models/ticket_model.dart';

enum TicketsStatus { initial, loading, success, failure }

/// Estado del tablero.
///
/// `tickets` son SIEMPRE los del sprint seleccionado sin filtrar: los filtros de
/// proyecto, área, prioridad y búsqueda se aplican en el cliente sobre esa
/// lista. Así los contadores de columna y el progreso del sprint siguen siendo
/// los del sprint completo aunque el usuario esté mirando una sola área, y
/// cambiar de filtro no cuesta una petición por toque.
class TicketsState {
  final TicketsStatus status;
  final List<TicketModel> tickets;
  final List<TicketProjectModel> projects;
  final List<SprintModel> sprints;

  /// `null` = todavía no sabemos qué sprint mostrar, o no hay sprints y se está
  /// mirando todo el histórico.
  final int? selectedSprintId;

  final String? projectFilter;
  final String? areaFilter;
  final String? priorityFilter;
  final String query;
  final String? errorMessage;

  const TicketsState({
    this.status = TicketsStatus.initial,
    this.tickets = const [],
    this.projects = const [],
    this.sprints = const [],
    this.selectedSprintId,
    this.projectFilter,
    this.areaFilter,
    this.priorityFilter,
    this.query = '',
    this.errorMessage,
  });

  SprintModel? get selectedSprint {
    for (final s in sprints) {
      if (s.id == selectedSprintId) return s;
    }
    return null;
  }

  SprintModel? get activeSprint {
    for (final s in sprints) {
      if (s.isActivo) return s;
    }
    return null;
  }

  bool get hasFilters =>
      projectFilter != null ||
      areaFilter != null ||
      priorityFilter != null ||
      query.trim().isNotEmpty;

  int get activeFilterCount => [
    projectFilter,
    areaFilter,
    priorityFilter,
    query.trim().isEmpty ? null : query,
  ].where((f) => f != null).length;

  /// Los tickets que se ven en el tablero una vez aplicados los filtros.
  List<TicketModel> get visibleTickets {
    final q = query.trim().toLowerCase();
    return tickets.where((t) {
      if (projectFilter != null && _projectKeyOf(t) != projectFilter) {
        return false;
      }
      if (areaFilter != null && t.area != areaFilter) return false;
      if (priorityFilter != null && t.priority != priorityFilter) return false;
      if (q.isNotEmpty) {
        final heno = '${t.code} ${t.title} ${t.description ?? ''}'
            .toLowerCase();
        if (!heno.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  List<TicketModel> ticketsEnColumna(String status) =>
      visibleTickets.where((t) => t.status == status).toList();

  /// Progreso del sprint: sobre TODOS sus tickets, no sobre los filtrados, y sin
  /// contar los descartados (que no son trabajo pendiente ni completado).
  int get sprintTotal => tickets.where((t) => t.status != 'descartado').length;

  int get sprintCompletados => tickets.where((t) => t.status == 'hecho').length;

  int get sprintProgreso =>
      sprintTotal == 0 ? 0 : ((sprintCompletados / sprintTotal) * 100).round();

  /// El proyecto sale del prefijo del código (`SGA-42` → `SGA`) porque el ticket
  /// trae `project_id`, no la clave, y el prefijo es justo lo que filtra el
  /// usuario.
  static String _projectKeyOf(TicketModel t) => t.code.split('-').first;

  TicketsState copyWith({
    TicketsStatus? status,
    List<TicketModel>? tickets,
    List<TicketProjectModel>? projects,
    List<SprintModel>? sprints,
    int? selectedSprintId,
    String? projectFilter,
    String? areaFilter,
    String? priorityFilter,
    String? query,
    String? errorMessage,
    bool clearSelectedSprint = false,
    bool clearProjectFilter = false,
    bool clearAreaFilter = false,
    bool clearPriorityFilter = false,
  }) {
    return TicketsState(
      status: status ?? this.status,
      tickets: tickets ?? this.tickets,
      projects: projects ?? this.projects,
      sprints: sprints ?? this.sprints,
      // Los `clear*` existen porque con `??` no hay forma de volver a null: al
      // quitar el filtro de proyecto se quedaba pegado el anterior y el tablero
      // seguía recargando con él.
      selectedSprintId: clearSelectedSprint
          ? null
          : (selectedSprintId ?? this.selectedSprintId),
      projectFilter: clearProjectFilter
          ? null
          : (projectFilter ?? this.projectFilter),
      areaFilter: clearAreaFilter ? null : (areaFilter ?? this.areaFilter),
      priorityFilter: clearPriorityFilter
          ? null
          : (priorityFilter ?? this.priorityFilter),
      query: query ?? this.query,
      // El error dura solo el emit que lo pone: si se arrastrara, un fallo viejo
      // seguiría en pantalla después de una recarga correcta.
      errorMessage: errorMessage,
    );
  }
}
