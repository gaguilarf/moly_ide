class TicketProjectModel {
  final int id;
  final String key;
  final String name;
  final String? targetServer;
  final int nextNumber;

  TicketProjectModel({
    required this.id,
    required this.key,
    required this.name,
    this.targetServer,
    required this.nextNumber,
  });

  factory TicketProjectModel.fromJson(Map<String, dynamic> json) => TicketProjectModel(
        id: json['id'] ?? 0,
        key: json['key'] ?? '',
        name: json['name'] ?? '',
        targetServer: json['target_server'],
        nextNumber: json['next_number'] ?? 1,
      );
}

class TicketEventModel {
  final int id;
  final int ticketId;
  final String at;
  final String actor;
  final String kind;
  final String? fromStatus;
  final String? toStatus;
  final String? note;

  TicketEventModel({
    required this.id,
    required this.ticketId,
    required this.at,
    required this.actor,
    required this.kind,
    this.fromStatus,
    this.toStatus,
    this.note,
  });

  factory TicketEventModel.fromJson(Map<String, dynamic> json) => TicketEventModel(
        id: json['id'] ?? 0,
        ticketId: json['ticket_id'] ?? 0,
        at: json['at'] ?? '',
        actor: json['actor'] ?? '',
        kind: json['kind'] ?? '',
        fromStatus: json['from_status'],
        toStatus: json['to_status'],
        note: json['note'],
      );
}

class TicketModel {
  final int id;
  final int projectId;
  final int? sprintId;
  final int number;
  final String code;
  final String title;
  final String? description;
  final String? plan;
  final String type;
  final String? area;
  final String priority;
  final String status;
  final String? assignee;
  final String reporter;
  final String source;
  final String? externalRef;
  final String createdAt;
  final String updatedAt;
  final String? resolvedAt;
  final List<TicketEventModel> events;

  TicketModel({
    required this.id,
    required this.projectId,
    this.sprintId,
    required this.number,
    required this.code,
    required this.title,
    this.description,
    this.plan,
    required this.type,
    this.area,
    required this.priority,
    required this.status,
    this.assignee,
    required this.reporter,
    required this.source,
    this.externalRef,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
    this.events = const [],
  });

  factory TicketModel.fromJson(Map<String, dynamic> json) => TicketModel(
        id: json['id'] ?? 0,
        projectId: json['project_id'] ?? 0,
        sprintId: json['sprint_id'],
        number: json['number'] ?? 0,
        code: json['code'] ?? '',
        title: json['title'] ?? '',
        description: json['description'],
        plan: json['plan'],
        type: json['type'] ?? 'feature',
        area: json['area'],
        priority: json['priority'] ?? 'media',
        status: json['status'] ?? 'backlog',
        assignee: json['assignee'],
        reporter: json['reporter'] ?? '',
        source: json['source'] ?? 'manual',
        externalRef: json['external_ref'],
        createdAt: json['created_at'] ?? '',
        updatedAt: json['updated_at'] ?? '',
        resolvedAt: json['resolved_at'],
        events: (json['events'] as List<dynamic>?)
                ?.map((e) => TicketEventModel.fromJson(e))
                .toList() ??
            [],
      );
}
