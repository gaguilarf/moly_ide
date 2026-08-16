import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
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
              'Claude Agent (Jetson)',
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
          final enCurso = state.tareasEnCurso;

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

                    // El flotante de tareas en curso. Va aquí y no como
                    // floatingActionButton del Scaffold para que quede sobre la
                    // conversación y no tape la caja de escribir.
                    if (enCurso.isNotEmpty)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _buildFlotanteTareas(context, enCurso),
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
            monoespaciada: true,
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
    bool monoespaciada = false,
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
        child: SelectableText(
          texto,
          style: monoespaciada
              ? GoogleFonts.firaCode(
                  fontSize: 12,
                  color: const Color(0xFFE0E0E0),
                  height: 1.35,
                )
              : GoogleFonts.outfit(
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

  /// Botón flotante con lo que Claude tiene entre manos. Al pulsarlo, la lista;
  /// al tocar una, se abre su conversación.
  Widget _buildFlotanteTareas(
    BuildContext context,
    List<ClaudeTaskModel> enCurso,
  ) {
    return FloatingActionButton.extended(
      heroTag: 'tareas-en-curso',
      backgroundColor: AppTheme.primaryPurple,
      onPressed: () => _mostrarTareas(context, enCurso),
      icon: const Icon(Icons.terminal_rounded, color: Colors.white),
      label: Text(
        '${enCurso.length} en curso',
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  void _mostrarTareas(BuildContext context, List<ClaudeTaskModel> enCurso) {
    final cubit = context.read<ClaudeCubit>();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (hojaCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Tareas en curso en el Jetson',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
            for (final t in enCurso)
              ListTile(
                leading: Icon(
                  t.status == 'bloqueado_esperando_humano'
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  color: t.status == 'bloqueado_esperando_humano'
                      ? const Color(0xFFFF9900)
                      : AppTheme.accentBlue,
                ),
                title: Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: Colors.white),
                ),
                subtitle: Text(
                  t.status == 'bloqueado_esperando_humano'
                      ? 'Esperando tu respuesta'
                      : 'Ejecutando',
                  style: GoogleFonts.firaCode(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(hojaCtx);
                  cubit.abrirConversacion(t.id);
                },
              ),
          ],
        ),
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
