import 'package:moly_ide/features/documentation/data/models/doc_models.dart';

enum DocsStatus { initial, loading, success, failure }

class DocsState {
  final DocsStatus status;
  final List<TemaDocModel> temas;

  /// Tema abierto. `null` = se está viendo la lista.
  final TemaDocModel? temaAbierto;
  final List<SeccionDocModel> secciones;
  final bool cargandoTema;

  /// Historial de la sección actualmente abierta en el modal. `null` =
  /// modal cerrado.
  final int? revisionesSeccionId;
  final List<RevisionDocModel> revisiones;
  final bool cargandoRevisiones;

  final String? errorMessage;

  const DocsState({
    this.status = DocsStatus.initial,
    this.temas = const [],
    this.temaAbierto,
    this.secciones = const [],
    this.cargandoTema = false,
    this.revisionesSeccionId,
    this.revisiones = const [],
    this.cargandoRevisiones = false,
    this.errorMessage,
  });

  DocsState copyWith({
    DocsStatus? status,
    List<TemaDocModel>? temas,
    TemaDocModel? temaAbierto,
    bool cerrarTema = false,
    List<SeccionDocModel>? secciones,
    bool? cargandoTema,
    int? revisionesSeccionId,
    bool cerrarRevisiones = false,
    List<RevisionDocModel>? revisiones,
    bool? cargandoRevisiones,
    String? errorMessage,
  }) {
    return DocsState(
      status: status ?? this.status,
      temas: temas ?? this.temas,
      // `cerrarTema` existe porque con `??` no habría forma de volver a la
      // lista: pasar null dejaría el tema anterior abierto.
      temaAbierto: cerrarTema ? null : (temaAbierto ?? this.temaAbierto),
      secciones: cerrarTema ? const [] : (secciones ?? this.secciones),
      cargandoTema: cargandoTema ?? this.cargandoTema,
      revisionesSeccionId: cerrarRevisiones
          ? null
          : (revisionesSeccionId ?? this.revisionesSeccionId),
      revisiones: cerrarRevisiones ? const [] : (revisiones ?? this.revisiones),
      cargandoRevisiones: cerrarRevisiones
          ? false
          : (cargandoRevisiones ?? this.cargandoRevisiones),
      errorMessage: errorMessage,
    );
  }
}
