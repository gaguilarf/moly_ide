class ClaudeAccountModel {
  final int id;
  final String alias;
  final String? email;
  final String status;
  final bool isPrimary;
  final String? lastUsedAt;

  ClaudeAccountModel({
    required this.id,
    required this.alias,
    this.email,
    required this.status,
    required this.isPrimary,
    this.lastUsedAt,
  });

  factory ClaudeAccountModel.fromJson(Map<String, dynamic> json) => ClaudeAccountModel(
        id: json['id'] ?? 0,
        alias: json['alias'] ?? '',
        email: json['email'],
        status: json['status'] ?? 'activa',
        isPrimary: json['is_primary'] ?? false,
        lastUsedAt: json['last_used_at'],
      );
}

class ClaudeTaskModel {
  final String id;
  final int? ticketId;
  final int? accountId;
  final String title;
  final String prompt;
  final String status;
  final String? pendingQuestion;
  final String? humanResponse;
  final String? executionLogs;
  final String createdAt;
  final String? finishedAt;

  ClaudeTaskModel({
    required this.id,
    this.ticketId,
    this.accountId,
    required this.title,
    required this.prompt,
    required this.status,
    this.pendingQuestion,
    this.humanResponse,
    this.executionLogs,
    required this.createdAt,
    this.finishedAt,
  });

  factory ClaudeTaskModel.fromJson(Map<String, dynamic> json) => ClaudeTaskModel(
        id: json['id']?.toString() ?? '',
        ticketId: json['ticket_id'],
        accountId: json['account_id'],
        title: json['title'] ?? '',
        prompt: json['prompt'] ?? '',
        status: json['status'] ?? 'pendiente',
        pendingQuestion: json['pending_question'],
        humanResponse: json['human_response'],
        executionLogs: json['execution_logs'],
        createdAt: json['created_at'] ?? '',
        finishedAt: json['finished_at'],
      );
}
