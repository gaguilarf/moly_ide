import 'package:moly_ide/features/documentation/data/models/doc_models.dart';

enum DocsStatus { initial, loading, success, failure }

class DocsState {
  final DocsStatus status;
  final List<TemaDocModel> temas;

  /// Tema abierto. `null` = se está viendo la lista.
  final TemaDocModel? temaAbierto;
  final List<SeccionDocModel> secciones;
  final bool cargandoTema;

  final String? errorMessage;

  const DocsState({
    this.status = DocsStatus.initial,
    this.temas = const [],
    this.temaAbierto,
    this.secciones = const [],
    this.cargandoTema = false,
    this.errorMessage,
  });

  DocsState copyWith({
    DocsStatus? status,
    List<TemaDocModel>? temas,
    TemaDocModel? temaAbierto,
    bool cerrarTema = false,
    List<SeccionDocModel>? secciones,
    bool? cargandoTema,
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
      errorMessage: errorMessage,
    );
  }
}
