import 'package:moly_ide/features/tickets/data/models/ticket_model.dart';

enum TicketsStatus { initial, loading, success, failure }

class TicketsState {
  final TicketsStatus status;
  final List<TicketModel> tickets;
  final List<TicketProjectModel> projects;
  final String? selectedProject;
  final String? errorMessage;

  const TicketsState({
    this.status = TicketsStatus.initial,
    this.tickets = const [],
    this.projects = const [],
    this.selectedProject,
    this.errorMessage,
  });

  TicketsState copyWith({
    TicketsStatus? status,
    List<TicketModel>? tickets,
    List<TicketProjectModel>? projects,
    String? selectedProject,
    String? errorMessage,
  }) {
    return TicketsState(
      status: status ?? this.status,
      tickets: tickets ?? this.tickets,
      projects: projects ?? this.projects,
      selectedProject: selectedProject ?? this.selectedProject,
      errorMessage: errorMessage,
    );
  }
}
