import 'package:moly_ide/features/claude_agent/data/models/claude_models.dart';

enum ClaudeStateStatus { initial, loading, success, failure }

/// Estados en los que Claude sigue teniendo la tarea entre manos.
const kEstadosEnCurso = {'ejecutando', 'bloqueado_esperando_humano'};

class ClaudeState {
  final ClaudeStateStatus status;
  final List<ClaudeAccountModel> accounts;
  final List<ClaudeTaskModel> tasks;
  final ClaudeTaskModel? activeTask;

  /// Trozos de salida que van llegando por el WebSocket, agrupados por tarea.
  ///
  /// Antes era una lista plana: los trozos de dos tareas a la vez se mezclaban
  /// en el mismo volcado y no habia forma de saber de cual era cada linea, ni
  /// de volver a una conversacion sin perder la otra.
  final Map<String, List<String>> chunksPorTarea;

  /// Conversación que se está mirando. `null` = ninguna, se enseña el vacío.
  final String? conversacionAbierta;

  final String? pendingQuestion; // Pregunta del freno duro en vivo
  final String? errorMessage;

  const ClaudeState({
    this.status = ClaudeStateStatus.initial,
    this.accounts = const [],
    this.tasks = const [],
    this.activeTask,
    this.chunksPorTarea = const {},
    this.conversacionAbierta,
    this.pendingQuestion,
    this.errorMessage,
  });

  /// La tarea cuya conversación está abierta.
  ClaudeTaskModel? get conversacion {
    if (conversacionAbierta == null) return null;
    for (final t in tasks) {
      if (t.id == conversacionAbierta) return t;
    }
    return null;
  }

  /// Lo que Claude tiene en marcha ahora mismo: lo que lista el botón flotante.
  List<ClaudeTaskModel> get tareasEnCurso =>
      tasks.where((t) => kEstadosEnCurso.contains(t.status)).toList();

  /// Salida de una tarea: lo que ha llegado en vivo si hay algo, y si no lo que
  /// quedó guardado. Así una conversación reabierta más tarde sigue teniendo su
  /// contenido aunque el WebSocket no estuviera escuchando cuando ocurrió.
  String salidaDe(ClaudeTaskModel tarea) {
    final envivo = chunksPorTarea[tarea.id];
    if (envivo != null && envivo.isNotEmpty) return envivo.join();
    return tarea.executionLogs ?? '';
  }

  /// La pregunta del freno duro que toca contestar en esta conversación, si la
  /// hay. Se mira contra la tarea abierta para no enseñar en una conversación
  /// la pregunta de otra.
  String? preguntaDe(ClaudeTaskModel tarea) {
    if (tarea.status != 'bloqueado_esperando_humano') return null;
    if (activeTask?.id == tarea.id && pendingQuestion != null) {
      return pendingQuestion;
    }
    return tarea.pendingQuestion;
  }

  ClaudeState copyWith({
    ClaudeStateStatus? status,
    List<ClaudeAccountModel>? accounts,
    List<ClaudeTaskModel>? tasks,
    ClaudeTaskModel? activeTask,
    bool clearActiveTask = false,
    Map<String, List<String>>? chunksPorTarea,
    String? conversacionAbierta,
    bool clearConversacion = false,
    String? pendingQuestion,
    bool clearQuestion = false,
    String? errorMessage,
  }) {
    return ClaudeState(
      status: status ?? this.status,
      accounts: accounts ?? this.accounts,
      tasks: tasks ?? this.tasks,
      // `clearActiveTask` existe porque con `??` no había forma de volver a
      // null: al terminar la tarea se quedaba pegada la anterior y
      // respondToHardStop seguía contestándole a una tarea muerta.
      activeTask: clearActiveTask ? null : (activeTask ?? this.activeTask),
      chunksPorTarea: chunksPorTarea ?? this.chunksPorTarea,
      conversacionAbierta: clearConversacion
          ? null
          : (conversacionAbierta ?? this.conversacionAbierta),
      pendingQuestion: clearQuestion
          ? null
          : (pendingQuestion ?? this.pendingQuestion),
      errorMessage: errorMessage,
    );
  }
}
