import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/core/widgets/texto_markdown.dart';
import 'package:moly_ide/features/auth/presentation/widgets/boton_cerrar_sesion.dart';
import 'package:moly_ide/features/documentation/data/models/doc_models.dart';
import 'package:moly_ide/features/documentation/presentation/cubit/docs_cubit.dart';
import 'package:moly_ide/features/documentation/presentation/cubit/docs_state.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';

/// Documentación viva: la lista de temas y, al tocar uno, sus secciones.
class DocsPage extends StatefulWidget {
  const DocsPage({super.key});

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  @override
  void initState() {
    super.initState();
    context.read<DocsCubit>().loadDocuments();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DocsCubit, DocsState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!, style: GoogleFonts.outfit()),
                backgroundColor: const Color(0xFFFF3366),
              ),
            );
        }
      },
      builder: (context, state) {
        final abierto = state.temaAbierto;

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            // Dentro de un tema, la flecha vuelve a la lista. Es una pestaña,
            // no una ruta, así que no hay Navigator del que tirar.
            leading: abierto == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Volver a los temas',
                    onPressed: () => context.read<DocsCubit>().volverALista(),
                  ),
            title: Text(
              abierto?.titulo ?? 'Documentación',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.system_update_rounded,
                  color: AppTheme.accentBlue,
                ),
                tooltip: 'Actualizar App',
                onPressed: () => UpdateDialog.show(context),
              ),
              IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppTheme.accentBlue,
                ),
                tooltip: 'Recargar',
                onPressed: () => context.read<DocsCubit>().loadDocuments(),
              ),
              const BotonCerrarSesion(),
            ],
          ),
          body: abierto == null ? _lista(state) : _tema(state, abierto),
        );
      },
    );
  }

  Widget _lista(DocsState state) {
    if (state.status == DocsStatus.loading && state.temas.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentBlue),
      );
    }

    if (state.temas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            state.status == DocsStatus.failure
                ? 'No se pudo cargar la documentación.\nTira de recargar cuando el Jetson responda.'
                : 'Todavía no hay ningún tema documentado.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<DocsCubit>().loadDocuments(),
      color: AppTheme.accentBlue,
      backgroundColor: AppTheme.surface,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: state.temas.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _fichaTema(state.temas[i]),
      ),
    );
  }

  Widget _fichaTema(TemaDocModel t) {
    return InkWell(
      onTap: () => context.read<DocsCubit>().abrirTema(t),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.titulo,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                _etiqueta(t.tipo, AppTheme.accentBlue),
              ],
            ),
            if (t.resumen != null && t.resumen!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                t.resumen!,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.white70,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (t.proyecto != null)
                  _etiqueta(t.proyecto!, AppTheme.primaryPurple),
                if (t.responsable != null) ...[
                  const SizedBox(width: 6),
                  _etiqueta(t.responsable!, AppTheme.textSecondary),
                ],
                const Spacer(),
                Text(
                  '${t.seccionesVisibles} secciones',
                  style: GoogleFonts.firaCode(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tema(DocsState state, TemaDocModel tema) {
    if (state.cargandoTema) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentBlue),
      );
    }

    if (state.secciones.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Este tema todavía no tiene secciones.',
            style: GoogleFonts.outfit(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: state.secciones.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _fichaSeccion(context, state.secciones[i]),
    );
  }

  Widget _fichaSeccion(BuildContext context, SeccionDocModel s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.titulo,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (s.frescura != null) ...[
                _etiquetaFrescura(s.frescura!),
                const SizedBox(width: 6),
              ],
              IconButton(
                icon: const Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                tooltip: 'Historial de esta sección',
                visualDensity: VisualDensity.compact,
                onPressed: () => _abrirHistorial(context, s),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Los cuerpos se guardan en markdown, con sus comillas invertidas y
          // sus listas: como texto plano se leían con las marcas a la vista.
          TextoMarkdown(s.cuerpo),
          if (s.audiencia != null) ...[
            const SizedBox(height: 10),
            _etiqueta('para ${s.audiencia}', AppTheme.textSecondary),
          ],
        ],
      ),
    );
  }

  void _abrirHistorial(BuildContext context, SeccionDocModel s) {
    final cubit = context.read<DocsCubit>();
    cubit.verHistorial(s.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: cubit,
        child: _HistorialSheet(titulo: s.titulo),
      ),
    ).whenComplete(() => cubit.cerrarHistorial());
  }

  /// La frescura dice si el contenido se puede creer todavía, así que va en
  /// color y no como texto suelto.
  Widget _etiquetaFrescura(String frescura) {
    final color = switch (frescura) {
      'fresca' => const Color(0xFF00FF66),
      'caduca' => const Color(0xFFFF5252),
      _ => const Color(0xFFFFB74D),
    };
    return _etiqueta(frescura.replaceAll('_', ' '), color);
  }

  Widget _etiqueta(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        texto,
        style: GoogleFonts.firaCode(fontSize: 10, color: color),
      ),
    );
  }
}

/// Historial de una sección: cada fila es una revisión (`doc_revisiones`),
/// más reciente primero (el backend ya la manda en ese orden).
class _HistorialSheet extends StatelessWidget {
  final String titulo;

  const _HistorialSheet({required this.titulo});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return BlocBuilder<DocsCubit, DocsState>(
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: AppTheme.accentBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Historial — $titulo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _cuerpo(state, scrollController)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _cuerpo(DocsState state, ScrollController scrollController) {
    if (state.cargandoRevisiones) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentBlue),
      );
    }
    if (state.revisiones.isEmpty) {
      return Center(
        child: Text(
          'Sin revisiones registradas todavía.',
          style: GoogleFonts.outfit(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      itemCount: state.revisiones.length,
      separatorBuilder: (_, _) =>
          const Divider(color: AppTheme.border, height: 20),
      itemBuilder: (context, i) => _filaRevision(state.revisiones[i]),
    );
  }

  Widget _filaRevision(RevisionDocModel r) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 8, color: AppTheme.accentBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    r.accion,
                    style: GoogleFonts.firaCode(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${r.actor} • ${_fecha(r.at)}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (r.motivo != null && r.motivo!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  r.motivo!,
                  style: GoogleFonts.outfit(fontSize: 13, color: Colors.white),
                ),
              ],
              if (r.detalleOculto) ...[
                const SizedBox(height: 4),
                Text(
                  'Detalle oculto: audiencia de entonces más restrictiva que la tuya.',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              if (r.ticketRef != null && r.ticketRef!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.primaryPurple),
                  ),
                  child: Text(
                    r.ticketRef!,
                    style: GoogleFonts.firaCode(
                      fontSize: 10,
                      color: AppTheme.primaryPurple,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _fecha(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      String p(int n) => n.toString().padLeft(2, '0');
      return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
    } catch (_) {
      return iso;
    }
  }
}
