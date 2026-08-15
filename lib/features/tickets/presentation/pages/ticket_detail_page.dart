import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/tickets/data/models/ticket_model.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_cubit.dart';
import 'package:moly_ide/features/tickets/presentation/ticket_catalog.dart';

class TicketDetailPage extends StatelessWidget {
  final TicketModel ticket;

  const TicketDetailPage({super.key, required this.ticket});

  Future<void> _showTransitionDialog(BuildContext context) async {
    // Solo los destinos que el backend acepta desde el estado actual.
    final nextStatuses = kTicketTransitions[ticket.status] ?? const <String>[];
    if (nextStatuses.isEmpty) return;

    // Cubit y Navigator se toman ANTES del primer await: después de esperar al
    // servidor, este `context` puede haber dejado de estar montado y buscarlos
    // por el árbol sería mirar un widget que ya no existe.
    final ticketsCubit = context.read<TicketsCubit>();
    final navegadorPagina = Navigator.of(context);

    String selected = nextStatuses.first;
    final noteController = TextEditingController();
    bool enviando = false;
    String? errorServidor;

    await showDialog<void>(
      context: context,
      // Mientras la petición está en vuelo no se puede descartar tocando fuera:
      // el diálogo es lo único que sabe si el cambio salió bien.
      barrierDismissible: false,
      builder: (dialContext) => StatefulBuilder(
        builder: (_, setDialState) {
          final faltaNota =
              selected == 'hecho' && noteController.text.trim().isEmpty;
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text(
              'Mover Estado de ${ticket.code}',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  dropdownColor: AppTheme.surfaceLight,
                  decoration: const InputDecoration(labelText: 'Nuevo Estado'),
                  items: nextStatuses
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            (kStatusLabel[s] ?? s).toUpperCase(),
                            style: GoogleFonts.firaCode(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: enviando
                      ? null
                      : (val) {
                          if (val != null) {
                            // El destino cambia: el rechazo anterior era del
                            // destino viejo y dejarlo puesto confunde.
                            setDialState(() {
                              selected = val;
                              errorServidor = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  enabled: !enviando,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: selected == 'hecho'
                        ? 'Nota de cierre (obligatoria)'
                        : 'Nota de transición',
                    hintText: 'Ej. Tests unitarios pasados...',
                    errorText: faltaNota
                        ? 'Para cerrar hace falta decir qué pasó: tests, commit o rama.'
                        : null,
                  ),
                  onChanged: (_) => setDialState(() {}),
                ),
                if (errorServidor != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3366).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFF3366)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: Color(0xFFFF3366),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            // El texto viene del `detail` del servidor: dice
                            // exactamente por qué rechazó el cambio.
                            'El servidor rechazó el cambio: $errorServidor',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: enviando ? null : () => Navigator.pop(dialContext),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                // El backend exige nota de cierre para 'hecho' (422). Sin este
                // freno el ticket parecía cerrarse y volvía a su estado al recargar.
                onPressed: (enviando || faltaNota)
                    ? null
                    : () async {
                        setDialState(() {
                          enviando = true;
                          errorServidor = null;
                        });

                        final nota = noteController.text.trim();
                        final error = await ticketsCubit.transitionTicket(
                          code: ticket.code,
                          toStatus: selected,
                          note: nota.isNotEmpty ? nota : null,
                        );

                        if (!dialContext.mounted) return;

                        // Solo se sale si el servidor aceptó. Antes se cerraba
                        // el diálogo y se volvía a la lista sin esperar, así que
                        // un rechazo se veía igual que un acierto.
                        if (error != null) {
                          setDialState(() {
                            enviando = false;
                            errorServidor = error;
                          });
                          return;
                        }

                        Navigator.pop(dialContext);
                        navegadorPagina
                            .pop(); // Volver a la lista, ya recargada
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryPurple,
                ),
                child: enviando
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );

    noteController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(
          ticket.code,
          style: GoogleFonts.firaCode(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.swap_horiz_rounded,
              color: AppTheme.accentBlue,
            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor(ticket.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: statusColor(ticket.status),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    ticket.status.toUpperCase(),
                    style: GoogleFonts.firaCode(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor(ticket.status),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: priorityColor(
                      ticket.priority,
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: priorityColor(ticket.priority),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    ticket.priority.toUpperCase(),
                    style: GoogleFonts.firaCode(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: priorityColor(ticket.priority),
                    ),
                  ),
                ),
                const Spacer(),
                if (ticket.area != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Área: ${ticket.area}',
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),
            Text(
              ticket.title,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
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
                    color: AppTheme.primaryPurple.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  // Lanzar resolución automática en el Jetson con Claude
                  final prompt =
                      'Por favor resuelve el ticket ${ticket.code}: "${ticket.title}".\n\nDescripción: ${ticket.description ?? "Sin descripción"}\nPlan: ${ticket.plan ?? "Sin plan"}';
                  context.read<ClaudeCubit>().launchTask(
                    title: 'Resolución ${ticket.code}',
                    prompt: prompt,
                    ticketId: ticket.id,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Claude ha iniciado la resolución en el Jetson...',
                        style: GoogleFonts.outfit(),
                      ),
                      backgroundColor: AppTheme.primaryPurple,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  'RESOLVER CON CLAUDE EN JETSON',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Descripción
            Text(
              'Descripción',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.accentBlue,
              ),
            ),
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
                ticket.description?.isNotEmpty == true
                    ? ticket.description!
                    : 'Sin descripción detallada.',
                style: GoogleFonts.outfit(color: Colors.white70, height: 1.4),
              ),
            ),

            const SizedBox(height: 16),

            // Plan
            Text(
              'Plan de Resolución',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryPurple,
              ),
            ),
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
                ticket.plan?.isNotEmpty == true
                    ? ticket.plan!
                    : 'Sin plan registrado.',
                style: GoogleFonts.firaCode(
                  fontSize: 12,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Historial de Eventos
            Text(
              'Historial de Eventos',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (ticket.events.isEmpty)
              Text(
                'No hay eventos registrados.',
                style: GoogleFonts.outfit(color: AppTheme.textSecondary),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ticket.events.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: AppTheme.border, height: 16),
                itemBuilder: (context, idx) {
                  final ev = ticket.events[idx];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 16,
                        color: AppTheme.accentBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${ev.actor} • ${ev.kind}',
                              style: GoogleFonts.firaCode(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            if (ev.note != null && ev.note!.isNotEmpty)
                              Text(
                                ev.note!,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
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
