import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/tickets/data/models/ticket_model.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_cubit.dart';

class TicketDetailPage extends StatelessWidget {
  final TicketModel ticket;

  const TicketDetailPage({super.key, required this.ticket});

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critica':
        return const Color(0xFFFF3366);
      case 'alta':
        return const Color(0xFFFF9900);
      case 'media':
        return const Color(0xFF00E5FF);
      case 'baja':
      default:
        return const Color(0xFF00FF66);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'backlog':
        return const Color(0xFF9E9E9E);
      case 'desarrollo':
        return const Color(0xFF00E5FF);
      case 'pruebas':
        return const Color(0xFFFF9900);
      case 'revision':
        return const Color(0xFF9E00FF);
      case 'hecho':
        return const Color(0xFF00FF66);
      case 'descartado':
        return const Color(0xFFFF3366);
      default:
        return Colors.white;
    }
  }

  void _showTransitionDialog(BuildContext context) {
    final nextStatuses = [
      'backlog',
      'desarrollo',
      'pruebas',
      'revision',
      'hecho',
      'descartado',
    ].where((s) => s != ticket.status).toList();

    String selected = nextStatuses.first;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialContext) => StatefulBuilder(
        builder: (context, setDialState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Mover Estado de ${ticket.code}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selected,
                dropdownColor: AppTheme.surfaceLight,
                decoration: const InputDecoration(labelText: 'Nuevo Estado'),
                items: nextStatuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase(), style: GoogleFonts.firaCode(fontSize: 13))))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialState(() => selected = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nota de transición',
                  hintText: 'Ej. Tests unitarios pasados...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialContext);
                context.read<TicketsCubit>().transitionTicket(
                      code: ticket.code,
                      toStatus: selected,
                      note: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
                    );
                Navigator.pop(context); // Volver a la lista
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryPurple),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(ticket.code, style: GoogleFonts.firaCode(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded, color: AppTheme.accentBlue),
            tooltip: 'Cambiar Estado',
            onPressed: () => _showTransitionDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(ticket.status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _getStatusColor(ticket.status), width: 1),
                  ),
                  child: Text(
                    ticket.status.toUpperCase(),
                    style: GoogleFonts.firaCode(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(ticket.status),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(ticket.priority).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _getPriorityColor(ticket.priority), width: 1),
                  ),
                  child: Text(
                    ticket.priority.toUpperCase(),
                    style: GoogleFonts.firaCode(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getPriorityColor(ticket.priority),
                    ),
                  ),
                ),
                const Spacer(),
                if (ticket.area != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Área: ${ticket.area}',
                      style: GoogleFonts.firaCode(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),
            Text(
              ticket.title,
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),

            const SizedBox(height: 20),

            // Action Button: Resolver con Claude
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: AppTheme.purpleBlueGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryPurple.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  // Lanzar resolución automática en el Jetson con Claude
                  final prompt = 'Por favor resuelve el ticket ${ticket.code}: "${ticket.title}".\n\nDescripción: ${ticket.description ?? "Sin descripción"}\nPlan: ${ticket.plan ?? "Sin plan"}';
                  context.read<ClaudeCubit>().launchTask(
                        title: 'Resolución ${ticket.code}',
                        prompt: prompt,
                        ticketId: ticket.id,
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Claude ha iniciado la resolución en el Jetson...', style: GoogleFonts.outfit()),
                      backgroundColor: AppTheme.primaryPurple,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                label: Text(
                  'RESOLVER CON CLAUDE EN JETSON',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Descripción
            Text('Descripción', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                ticket.description?.isNotEmpty == true ? ticket.description! : 'Sin descripción detallada.',
                style: GoogleFonts.outfit(color: Colors.white70, height: 1.4),
              ),
            ),

            const SizedBox(height: 16),

            // Plan
            Text('Plan de Resolución', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryPurple)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                ticket.plan?.isNotEmpty == true ? ticket.plan! : 'Sin plan registrado.',
                style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white70, height: 1.4),
              ),
            ),

            const SizedBox(height: 24),

            // Historial de Eventos
            Text('Historial de Eventos', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            if (ticket.events.isEmpty)
              Text('No hay eventos registrados.', style: GoogleFonts.outfit(color: AppTheme.textSecondary))
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ticket.events.length,
                separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 16),
                itemBuilder: (context, idx) {
                  final ev = ticket.events[idx];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.history_rounded, size: 16, color: AppTheme.accentBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${ev.actor} • ${ev.kind}',
                              style: GoogleFonts.firaCode(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                            ),
                            if (ev.note != null && ev.note!.isNotEmpty)
                              Text(ev.note!, style: GoogleFonts.outfit(fontSize: 13, color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
