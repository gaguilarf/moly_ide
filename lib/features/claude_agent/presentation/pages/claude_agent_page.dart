import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/core/widgets/texto_markdown.dart';
import 'package:moly_ide/features/auth/presentation/widgets/boton_cerrar_sesion.dart';
import 'package:moly_ide/features/claude_agent/data/models/claude_models.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_cubit.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_state.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';

class ClaudeAgentPage extends StatefulWidget {
  const ClaudeAgentPage({super.key});

  @override
  State<ClaudeAgentPage> createState() => _ClaudeAgentPageState();
}

class _ClaudeAgentPageState extends State<ClaudeAgentPage> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _hardStopController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    context.read<ClaudeCubit>().loadDashboardData();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSendPrompt() {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;
    _promptController.clear();
    context.read<ClaudeCubit>().launchTask(
      title: text.length > 30 ? '${text.substring(0, 30)}...' : text,
      prompt: text,
    );
  }

  void _handleRespondHardStop() {
    final text = _hardStopController.text.trim();
    if (text.isEmpty) return;
    _hardStopController.clear();
    context.read<ClaudeCubit>().respondToHardStop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: AppTheme.accentBlue,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Claude Agent',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
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
              Icons.add_comment_rounded,
              color: AppTheme.accentBlue,
            ),
            tooltip: 'Chat nuevo',
            // Cierra la conversación abierta y deja la pantalla en blanco. La
            // tarea se crea al enviar el primer mensaje: sin esto, una vez
            // abierto un chat no había forma de volver al estado inicial.
            onPressed: () => context.read<ClaudeCubit>().nuevaConversacion(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentBlue),
            tooltip: 'Recargar',
            onPressed: () => context.read<ClaudeCubit>().loadDashboardData(),
          ),
          const BotonCerrarSesion(),
        ],
      ),
      body: BlocConsumer<ClaudeCubit, ClaudeState>(
        listener: (context, state) {
          _scrollToBottom();
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: const Color(0xFFFF3366),
              ),
            );
          }
        },
        builder: (context, state) {
          final conversacion = state.conversacion;

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: conversacion == null
                          ? _buildVacio()
                          : _buildConversacion(state, conversacion),
                    ),

                    // El flotante. Va aquí y no como floatingActionButton del
                    // Scaffold para que quede sobre la conversación sin tapar
                    // la caja de escribir. Se enseña siempre que haya alguna
                    // conversación, no solo con tareas vivas: si no, a un chat
                    // terminado no habría por donde volver ni como borrarlo.
                    if (state.tasks.isNotEmpty)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _buildFlotanteTareas(context, state),
                      ),
                  ],
                ),
              ),

              _buildBottomInputBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Ninguna conversación abierta.\n'
          'Escribe abajo para pedirle algo a Claude en el Jetson.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  /// La conversación: lo que pediste, lo que Claude va respondiendo, y —si se
  /// ha parado a preguntar— su pregunta con la caja para contestarle.
  Widget _buildConversacion(ClaudeState state, ClaudeTaskModel tarea) {
    final salida = state.salidaDe(tarea);
    final pregunta = state.preguntaDe(tarea);
    final esperando = tarea.status == 'ejecutando' && salida.isEmpty;

    return ListView(
      controller: _logScrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      children: [
        _burbuja(texto: tarea.prompt, mio: true),

        if (esperando) _pensando(),
        if (salida.isNotEmpty)
          _burbuja(
            texto: salida,
            mio: false,
            markdown: true,
            fallo: tarea.status == 'fallido',
          ),

        if (pregunta != null) _buildHardStopCard(pregunta),

        if (tarea.status == 'fallido' && salida.isEmpty)
          _burbuja(
            texto: 'La tarea falló sin dejar salida.',
            mio: false,
            fallo: true,
          ),
      ],
    );
  }

  Widget _burbuja({
    required String texto,
    required bool mio,
    bool markdown = false,
    bool fallo = false,
  }) {
    return Align(
      alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: mio
              ? AppTheme.primaryPurple.withValues(alpha: 0.25)
              : (fallo
                    ? const Color(0xFFFF5252).withValues(alpha: 0.12)
                    : AppTheme.surface),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: mio
                ? AppTheme.primaryPurple
                : (fallo ? const Color(0xFFFF5252) : AppTheme.border),
          ),
        ),
        // Lo que responde Claude viene en markdown; lo que escribes tú es
        // texto tal cual y se deja como está, para que unos asteriscos que
        // hayas escrito a propósito no desaparezcan al pintarlos.
        child: markdown
            ? TextoMarkdown(texto, colorTexto: const Color(0xFFE0E0E0))
            : SelectableText(
                texto,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.white,
                  height: 1.35,
                ),
              ),
      ),
    );
  }

  Widget _pensando() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Claude está trabajando…',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Botón flotante: cuántas tareas hay en marcha, y puerta a la lista de
  /// conversaciones.
  Widget _buildFlotanteTareas(BuildContext context, ClaudeState state) {
    final enCurso = state.tareasEnCurso.length;

    return FloatingActionButton.extended(
      heroTag: 'conversaciones',
      backgroundColor: enCurso > 0
          ? AppTheme.primaryPurple
          : AppTheme.surfaceLight,
      onPressed: () => _mostrarConversaciones(context, state),
      icon: Icon(
        enCurso > 0 ? Icons.terminal_rounded : Icons.forum_rounded,
        color: Colors.white,
      ),
      label: Text(
        enCurso > 0 ? '$enCurso en curso' : '${state.tasks.length} chats',
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  void _mostrarConversaciones(BuildContext context, ClaudeState state) {
    final cubit = context.read<ClaudeCubit>();
    final enCurso = state.tareasEnCurso;
    final anteriores = state.tasks
        .where((t) => !kEstadosEnCurso.contains(t.status))
        .toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (hojaCtx) => SafeArea(
        child: ConstrainedBox(
          // Sin tope, una lista larga de chats ocuparía la pantalla entera.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(hojaCtx).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Conversaciones',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (anteriores.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(hojaCtx);
                          _confirmarBorrarTerminadas(
                            context,
                            cubit,
                            anteriores.length,
                          );
                        },
                        icon: const Icon(
                          Icons.delete_sweep_rounded,
                          size: 18,
                          color: Color(0xFFFF5252),
                        ),
                        label: Text(
                          'Borrar terminadas',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: const Color(0xFFFF5252),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (enCurso.isNotEmpty) _rotulo('En curso'),
                    for (final t in enCurso)
                      _filaConversacion(context, hojaCtx, cubit, t, state),
                    if (anteriores.isNotEmpty) _rotulo('Anteriores'),
                    for (final t in anteriores)
                      _filaConversacion(context, hojaCtx, cubit, t, state),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rotulo(String texto) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(
      texto.toUpperCase(),
      style: GoogleFonts.firaCode(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: AppTheme.textSecondary,
      ),
    ),
  );

  Widget _filaConversacion(
    BuildContext pageCtx,
    BuildContext hojaCtx,
    ClaudeCubit cubit,
    ClaudeTaskModel t,
    ClaudeState state,
  ) {
    // Solo se protege mientras se ejecuta. Una bloqueada esperando respuesta sí
    // se puede borrar: si no, una que se quedó esperando algo que nunca llegó
    // se veía para siempre sin forma de quitarla.
    final ejecutando = t.status == 'ejecutando';
    final abierta = state.conversacionAbierta == t.id;

    return ListTile(
      selected: abierta,
      selectedTileColor: AppTheme.primaryPurple.withValues(alpha: 0.12),
      leading: Icon(_iconoDe(t.status), color: _colorDe(t.status)),
      title: Text(
        t.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.outfit(color: Colors.white),
      ),
      subtitle: Text(
        _etiquetaDe(t.status),
        style: GoogleFonts.firaCode(
          fontSize: 11,
          color: AppTheme.textSecondary,
        ),
      ),
      trailing: IconButton(
        icon: Icon(
          Icons.delete_outline_rounded,
          // Una tarea viva no se puede borrar: su subproceso sigue escribiendo.
          // Se enseña apagada en vez de esconderla, para que se vea que la
          // opción existe y por qué no está disponible.
          color: ejecutando ? AppTheme.textSecondary : const Color(0xFFFF5252),
        ),
        tooltip: ejecutando
            ? 'No se puede: se está ejecutando'
            : 'Borrar conversación',
        onPressed: ejecutando
            ? null
            : () {
                Navigator.pop(hojaCtx);
                _confirmarBorrar(pageCtx, cubit, t);
              },
      ),
      onTap: () {
        Navigator.pop(hojaCtx);
        cubit.abrirConversacion(t.id);
      },
    );
  }

  static IconData _iconoDe(String status) => switch (status) {
    'ejecutando' => Icons.play_circle_fill_rounded,
    'bloqueado_esperando_humano' => Icons.pause_circle_filled_rounded,
    'fallido' => Icons.error_rounded,
    'completado' => Icons.check_circle_rounded,
    _ => Icons.schedule_rounded,
  };

  static Color _colorDe(String status) => switch (status) {
    'ejecutando' => AppTheme.accentBlue,
    'bloqueado_esperando_humano' => const Color(0xFFFF9900),
    'fallido' => const Color(0xFFFF5252),
    'completado' => const Color(0xFF00FF66),
    _ => AppTheme.textSecondary,
  };

  static String _etiquetaDe(String status) => switch (status) {
    'ejecutando' => 'Ejecutando',
    'bloqueado_esperando_humano' => 'Esperando tu respuesta',
    'fallido' => 'Fallo',
    'completado' => 'Terminada',
    _ => 'Pendiente',
  };

  void _confirmarBorrar(
    BuildContext context,
    ClaudeCubit cubit,
    ClaudeTaskModel t,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Borrar conversación',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: Text(
          'Se borrará «${t.title}» y lo que Claude respondió. No se puede deshacer.',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialContext);
              final error = await cubit.borrarConversacion(t.id);
              if (error != null) _avisar(context, error);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
            ),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
  }

  void _confirmarBorrarTerminadas(
    BuildContext context,
    ClaudeCubit cubit,
    int cuantas,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Borrar terminadas',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: Text(
          'Se borrarán $cuantas conversaciones ya cerradas. Las que sigan en '
          'curso se quedan. No se puede deshacer.',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialContext);
              final error = await cubit.borrarTerminadas();
              if (error != null) _avisar(context, error);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
            ),
            child: Text('Borrar $cuantas'),
          ),
        ],
      ),
    );
  }

  void _avisar(BuildContext context, String mensaje) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje, style: GoogleFonts.outfit()),
        backgroundColor: const Color(0xFFFF3366),
      ),
    );
  }

  Widget _buildHardStopCard(String question) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E142B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryPurple, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryPurple.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pause_circle_filled_rounded,
                color: Color(0xFFFF9900),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'FRENO DURO • CLAUDE SOLICITA RESPUESTA',
                style: GoogleFonts.firaCode(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFF9900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            question,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hardStopController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Escribe tu respuesta para Claude...',
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    filled: true,
                    fillColor: AppTheme.surfaceLight,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _handleRespondHardStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryPurple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  'CONTINUAR',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Instrucción o auditoría para Claude en Jetson...',
                hintStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
                filled: true,
                fillColor: AppTheme.surfaceLight,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _handleSendPrompt(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.purpleBlueGradient,
            ),
            child: IconButton(
              icon: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: _handleSendPrompt,
            ),
          ),
        ],
      ),
    );
  }
}
