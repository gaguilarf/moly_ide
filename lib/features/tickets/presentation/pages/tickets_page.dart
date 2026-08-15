import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:moly_ide/features/tickets/presentation/pages/ticket_detail_page.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';

class TicketsPage extends StatefulWidget {
  const TicketsPage({super.key});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  String? _selectedProject;

  @override
  void initState() {
    super.initState();
    context.read<TicketsCubit>().loadTickets();
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

  void _showCreateDialog() {
    final cubit = context.read<TicketsCubit>();
    final projects = cubit.state.projects;
    String selectedProj = projects.isNotEmpty ? projects.first.key : 'SGA';
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final planController = TextEditingController();
    String selectedArea = 'back';
    String selectedPriority = 'media';

    showDialog(
      context: context,
      builder: (dialCtx) => StatefulBuilder(
        builder: (context, setDialState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Nuevo Ticket', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedProj,
                  dropdownColor: AppTheme.surfaceLight,
                  decoration: const InputDecoration(labelText: 'Proyecto'),
                  items: projects
                      .map((p) => DropdownMenuItem(value: p.key, child: Text('${p.key} - ${p.name}', style: GoogleFonts.firaCode(fontSize: 12))))
                      .toList(),
                  onChanged: (val) => setDialState(() => selectedProj = val!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: planController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Plan (opcional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedArea,
                        dropdownColor: AppTheme.surfaceLight,
                        decoration: const InputDecoration(labelText: 'Área'),
                        items: ['back', 'front', 'mobile', 'infra', 'qa', 'pm', 'datos', 'diseno']
                            .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                            .toList(),
                        onChanged: (val) => setDialState(() => selectedArea = val!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedPriority,
                        dropdownColor: AppTheme.surfaceLight,
                        decoration: const InputDecoration(labelText: 'Prioridad'),
                        items: ['baja', 'media', 'alta', 'critica']
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (val) => setDialState(() => selectedPriority = val!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                cubit.createTicket(
                  projectKey: selectedProj,
                  title: titleController.text.trim(),
                  description: descController.text.trim(),
                  plan: planController.text.trim(),
                  area: selectedArea,
                  priority: selectedPriority,
                );
                Navigator.pop(dialCtx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryPurple),
              child: const Text('Crear'),
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
        title: Text(
          'Tablero de Tickets',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
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
            onPressed: () => context.read<TicketsCubit>().loadTickets(project: _selectedProject),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        backgroundColor: AppTheme.primaryPurple,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('NUEVO TICKET', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: BlocBuilder<TicketsCubit, TicketsState>(
        builder: (context, state) {
          if (state.status == TicketsStatus.loading && state.tickets.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.accentBlue));
          }

          return Column(
            children: [
              // Project Filter Chips
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('TODOS', style: GoogleFonts.firaCode(fontSize: 11)),
                        selected: _selectedProject == null,
                        selectedColor: AppTheme.primaryPurple.withOpacity(0.3),
                        onSelected: (selected) {
                          setState(() => _selectedProject = null);
                          context.read<TicketsCubit>().loadTickets();
                        },
                      ),
                    ),
                    ...state.projects.map((p) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(p.key, style: GoogleFonts.firaCode(fontSize: 11)),
                            selected: _selectedProject == p.key,
                            selectedColor: AppTheme.primaryPurple.withOpacity(0.3),
                            onSelected: (selected) {
                              setState(() => _selectedProject = selected ? p.key : null);
                              context.read<TicketsCubit>().loadTickets(project: _selectedProject);
                            },
                          ),
                        )),
                  ],
                ),
              ),

              // Kanban Board / List
              Expanded(
                child: state.tickets.isEmpty
                    ? Center(
                        child: Text(
                          'No hay tickets registrados.',
                          style: GoogleFonts.outfit(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: state.tickets.length,
                        itemBuilder: (context, index) {
                          final ticket = state.tickets[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: AppTheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: AppTheme.border.withOpacity(0.6)),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TicketDetailPage(ticket: ticket),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          ticket.code,
                                          style: GoogleFonts.firaCode(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.accentBlue,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(ticket.status).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            ticket.status.toUpperCase(),
                                            style: GoogleFonts.firaCode(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: _getStatusColor(ticket.status),
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        if (ticket.area != null)
                                          Text(
                                            ticket.area!,
                                            style: GoogleFonts.firaCode(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      ticket.title,
                                      style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (ticket.description != null && ticket.description!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        ticket.description!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
