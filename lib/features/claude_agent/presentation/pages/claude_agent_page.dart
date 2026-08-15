import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
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
            const Icon(Icons.auto_awesome_rounded, color: AppTheme.accentBlue, size: 20),
            const SizedBox(width: 8),
            Text('Claude Agent (Jetson)', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_rounded, color: AppTheme.accentBlue),
            tooltip: 'Actualizar App',
            onPressed: () => UpdateDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentBlue),
            tooltip: 'Recargar',
            onPressed: () => context.read<ClaudeCubit>().loadDashboardData(),
          ),
        ],
      ),
      body: BlocConsumer<ClaudeCubit, ClaudeState>(
        listener: (context, state) {
          if (state.liveLogs.isNotEmpty) {
            _scrollToBottom();
          }
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!), backgroundColor: const Color(0xFFFF3366)),
            );
          }
        },
        builder: (context, state) {
          return Column(
            children: [
              // Dual-Account Status Bar
              _buildAccountsBar(state),

              // Interactive Hard-Stop Alert Card (Human-in-the-Loop)
              if (state.pendingQuestion != null) _buildHardStopCard(state.pendingQuestion!),

              // Live Terminal / Logs Output
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: state.liveLogs.isEmpty
                      ? Center(
                          child: Text(
                            'No hay tareas activas en ejecución.\nEnvía un prompt o selecciona un ticket.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          controller: _logScrollController,
                          itemCount: state.liveLogs.length,
                          itemBuilder: (context, idx) {
                            final log = state.liveLogs[idx];
                            return Text(
                              log,
                              style: GoogleFonts.firaCode(fontSize: 12, color: const Color(0xFFE0E0E0), height: 1.3),
                            );
                          },
                        ),
                ),
              ),

              // Bottom Prompt Input Bar
              _buildBottomInputBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAccountsBar(ClaudeState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.surface,
      child: Row(
        children: [
          Text('CUENTAS:', style: GoogleFonts.firaCode(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
          const SizedBox(width: 8),
          if (state.accounts.isEmpty)
            Text('Sin cuentas registradas', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary))
          else
            Expanded(
              child: Wrap(
                spacing: 8,
                children: state.accounts.map((acc) {
                  final isActive = acc.status == 'activa';
                  final isPrimary = acc.isPrimary;
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: isActive ? AppTheme.surfaceLight : const Color(0xFFFF3366).withOpacity(0.2),
                    avatar: Icon(
                      isActive ? Icons.check_circle_rounded : Icons.warning_rounded,
                      size: 14,
                      color: isActive ? const Color(0xFF00FF66) : const Color(0xFFFF3366),
                    ),
                    label: Text(
                      '${acc.alias}${isPrimary ? ' (P)' : ' (S)'}',
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        color: isActive ? Colors.white : const Color(0xFFFF3366),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
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
              const Icon(Icons.pause_circle_filled_rounded, color: Color(0xFFFF9900), size: 18),
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
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
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
                    hintStyle: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.surfaceLight,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _handleRespondHardStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                child: Text('CONTINUAR', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
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
                hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppTheme.textSecondary),
                filled: true,
                fillColor: AppTheme.surfaceLight,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _handleSendPrompt,
            ),
          ),
        ],
      ),
    );
  }
}
