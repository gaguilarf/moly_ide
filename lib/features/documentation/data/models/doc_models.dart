/// Documentación viva: temas con secciones, servidos por la API de Moly desde
/// el Jetson (`/documentacion/temas`).
///
/// Sustituye al recorrido de ficheros `.md` que hacía `/docs`: aquello leía un
/// directorio del disco que ya no existe —era `docs_brittanygroup`, retirado—,
/// así que la pestaña salía siempre vacía.
class TemaDocModel {
  final int id;
  final String slug;
  final String titulo;
  final String tipo;
  final String? resumen;
  final String? responsable;
  final String? proyecto;
  final String estado;
  final int seccionesVisibles;

  const TemaDocModel({
    required this.id,
    required this.slug,
    required this.titulo,
    required this.tipo,
    this.resumen,
    this.responsable,
    this.proyecto,
    required this.estado,
    required this.seccionesVisibles,
  });

  factory TemaDocModel.fromJson(Map<String, dynamic> json) => TemaDocModel(
    id: json['id'] ?? 0,
    slug: json['slug'] ?? '',
    titulo: json['titulo'] ?? '',
    tipo: json['tipo'] ?? '',
    resumen: json['resumen'],
    responsable: json['responsable'],
    proyecto: json['proyecto'],
    estado: json['estado'] ?? 'activo',
    seccionesVisibles: json['secciones_visibles'] ?? 0,
  );
}

class SeccionDocModel {
  final int id;
  final int orden;
  final String titulo;
  final String cuerpo;
  final String? audiencia;

  /// `sin_verificar`, `fresca`, `caduca`… Es lo que dice si el contenido se
  /// puede creer todavía, así que se enseña junto al título.
  final String? frescura;

  const SeccionDocModel({
    required this.id,
    required this.orden,
    required this.titulo,
    required this.cuerpo,
    this.audiencia,
    this.frescura,
  });

  factory SeccionDocModel.fromJson(Map<String, dynamic> json) =>
      SeccionDocModel(
        id: json['id'] ?? 0,
        orden: json['orden'] ?? 0,
        titulo: json['titulo'] ?? '',
        cuerpo: json['cuerpo'] ?? '',
        audiencia: json['audiencia'],
        frescura: json['frescura'],
      );
}

/// Una entrada de `doc_revisiones`: qué cambió en una sección, quién y por
/// qué. El backend ya oculta `cuerpoAnterior`/`motivo` si la audiencia de
/// entonces era más restrictiva que la de quien consulta (`detalleOculto`).
class RevisionDocModel {
  final int id;
  final String at;
  final String actor;
  final String accion;
  final String? cuerpoAnterior;
  final String? motivo;
  final String? ticketRef;
  final bool detalleOculto;

  const RevisionDocModel({
    required this.id,
    required this.at,
    required this.actor,
    required this.accion,
    this.cuerpoAnterior,
    this.motivo,
    this.ticketRef,
    required this.detalleOculto,
  });

  factory RevisionDocModel.fromJson(Map<String, dynamic> json) =>
      RevisionDocModel(
        id: json['id'] ?? 0,
        at: json['at'] ?? '',
        actor: json['actor'] ?? '',
        accion: json['accion'] ?? '',
        cuerpoAnterior: json['cuerpo_anterior'],
        motivo: json['motivo'],
        ticketRef: json['ticket_ref'],
        detalleOculto: json['detalle_oculto'] ?? false,
      );
}
