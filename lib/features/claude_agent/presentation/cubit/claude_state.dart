import 'package:moly_ide/features/claude_agent/data/models/claude_models.dart';

enum ClaudeStateStatus { initial, loading, success, failure }

class ClaudeState {
  final ClaudeStateStatus status;
  final List<ClaudeAccountModel> accounts;
  final List<ClaudeTaskModel> tasks;
  final ClaudeTaskModel? activeTask;
  final List<String> liveLogs;
  final String? pendingQuestion; // Pregunta del freno duro en vivo
  final String? errorMessage;

  const ClaudeState({
    this.status = ClaudeStateStatus.initial,
    this.accounts = const [],
    this.tasks = const [],
    this.activeTask,
    this.liveLogs = const [],
    this.pendingQuestion,
    this.errorMessage,
  });

  ClaudeState copyWith({
    ClaudeStateStatus? status,
    List<ClaudeAccountModel>? accounts,
    List<ClaudeTaskModel>? tasks,
    ClaudeTaskModel? activeTask,
    bool clearActiveTask = false,
    List<String>? liveLogs,
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
      liveLogs: liveLogs ?? this.liveLogs,
      pendingQuestion: clearQuestion
          ? null
          : (pendingQuestion ?? this.pendingQuestion),
      errorMessage: errorMessage,
    );
  }
}
