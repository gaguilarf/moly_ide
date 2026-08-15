import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_cubit.dart';
import 'package:moly_ide/features/tickets/data/models/ticket_model.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:moly_ide/features/tickets/presentation/pages/ticket_detail_page.dart';
import 'package:moly_ide/features/tickets/presentation/ticket_catalog.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';

/// Tablero de tickets: un sprint a la vez y una columna por estado.
///
/// El equivalente móvil de las columnas del panel son pestañas deslizables: en
/// un teléfono no caben cinco columnas a la vez, pero el modelo mental (cada
/// estado su montón, con su contador) es el mismo.
class TicketsPage extends StatefulWidget {
  const TicketsPage({super.key});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kBoardColumns.length, vsync: this);
    context.read<TicketsCubit>().loadBoard();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _abrirDetalle(TicketModel ticket) {
    // Los cubits viven bajo el Navigator (en MainNavigationPage), así que una
    // ruta empujada NO los hereda: hay que pasárselos a mano o el detalle
    // revienta al tocar "cambiar estado" o "resolver con Claude".
    final ticketsCubit = context.read<TicketsCubit>();
    final claudeCubit = context.read<ClaudeCubit>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider<TicketsCubit>.value(value: ticketsCubit),
            BlocProvider<ClaudeCubit>.value(value: claudeCubit),
          ],
          child: TicketDetailPage(ticket: ticket),
        ),
      ),
    );
  }

  void _limpiarFiltros() {
    _searchController.clear();
    context.read<TicketsCubit>().clearFilters();
  }

  void _abrirFiltros() {
    final cubit = context.read<TicketsCubit>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => BlocProvider<TicketsCubit>.value(
        value: cubit,
        child: BlocBuilder<TicketsCubit, TicketsState>(
          builder: (ctx, state) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Filtros',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      if (state.hasFilters)
                        TextButton.icon(
                          onPressed: _limpiarFiltros,
                          icon: const Icon(
                            Icons.filter_alt_off_rounded,
                            size: 16,
                          ),
                          label: const Text('Limpiar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _GrupoFiltro(
                    titulo: 'Proyecto',
                    opciones: [for (final p in state.projects) (p.key, p.key)],
                    seleccionada: state.projectFilter,
                    onSelect: cubit.setProjectFilter,
                  ),
                  _GrupoFiltro(
                    titulo: 'Área',
                    opciones: [
                      for (final a in kTicketAreas) (a, kAreaLabel[a] ?? a),
                    ],
                    seleccionada: state.areaFilter,
                    onSelect: cubit.setAreaFilter,
                    colorDe: areaColor,
                  ),
                  _GrupoFiltro(
                    titulo: 'Prioridad',
                    opciones: [
                      for (final p in kTicketPriorities)
                        (p, kPriorityLabel[p] ?? p),
                    ],
                    seleccionada: state.priorityFilter,
                    onSelect: cubit.setPriorityFilter,
                    colorDe: priorityColor,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: Text(
                        'VER ${state.visibleTickets.length} TICKETS',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateDialog() {
    final cubit = context.read<TicketsCubit>();
    final projects = cubit.state.projects;
    if (projects.isEmpty) return;
    // El proyecto que se está filtrando es el que se quiere crear casi siempre.
    String selectedProj = cubit.state.projectFilter ?? projects.first.key;
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final planController = TextEditingController();
    String selectedArea = cubit.state.areaFilter ?? 'back';
    String selectedPriority = 'media';

    showDialog(
      context: context,
      builder: (dialCtx) => StatefulBuilder(
        builder: (context, setDialState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(
            'Nuevo Ticket',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProj,
                  dropdownColor: AppTheme.surfaceLight,
                  decoration: const InputDecoration(labelText: 'Proyecto'),
                  items: projects
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.key,
                          child: Text(
                            '${p.key} - ${p.name}',
                            style: GoogleFonts.firaCode(fontSize: 12),
                          ),
                        ),
                      )
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
                  decoration: const InputDecoration(
                    labelText: 'Plan (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedArea,
                        dropdownColor: AppTheme.surfaceLight,
                        decoration: const InputDecoration(labelText: 'Área'),
                        items: kTicketAreas
                            .map(
                              (a) => DropdownMenuItem(
                                value: a,
                                child: Text(kAreaLabel[a] ?? a),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setDialState(() => selectedArea = val!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedPriority,
                        dropdownColor: AppTheme.surfaceLight,
                        decoration: const InputDecoration(
                          labelText: 'Prioridad',
                        ),
                        items: kTicketPriorities
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(kPriorityLabel[p] ?? p),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setDialState(() => selectedPriority = val!),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
              ),
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
            onPressed: () => context.read<TicketsCubit>().loadBoard(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        backgroundColor: AppTheme.primaryPurple,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'NUEVO TICKET',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: BlocConsumer<TicketsCubit, TicketsState>(
        listenWhen: (previo, actual) => actual.errorMessage != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!, style: GoogleFonts.outfit()),
                backgroundColor: const Color(0xFFFF3366),
              ),
            );
        },
        builder: (context, state) {
          final primeraCarga =
              state.status == TicketsStatus.loading && state.sprints.isEmpty;
          if (primeraCarga) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accentBlue),
            );
          }

          if (state.status == TicketsStatus.failure && state.tickets.isEmpty) {
            return _Reintentar(
              mensaje: state.errorMessage ?? 'No se pudo cargar el tablero.',
              onRetry: () => context.read<TicketsCubit>().loadBoard(),
            );
          }

          return Column(
            children: [
              _SprintHeader(state: state),
              _BarraFiltros(
                state: state,
                searchController: _searchController,
                onAbrirFiltros: _abrirFiltros,
                onLimpiar: _limpiarFiltros,
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: AppTheme.border,
                labelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: GoogleFonts.outfit(fontSize: 13),
                tabs: [
                  for (final columna in kBoardColumns)
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(kStatusLabel[columna] ?? columna),
                          const SizedBox(width: 6),
                          _Contador(
                            valor: state.ticketsEnColumna(columna).length,
                            color: statusColor(columna),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    for (final columna in kBoardColumns)
                      _ColumnaTickets(
                        tickets: state.ticketsEnColumna(columna),
                        vacio: state.tickets.isEmpty
                            ? 'Este sprint no tiene tickets todavía.'
                            : state.hasFilters
                            ? 'Ningún ticket de esta columna pasa los filtros.'
                            : 'Nada en ${kStatusLabel[columna] ?? columna}.',
                        onRefresh: () => context.read<TicketsCubit>().loadBoard(
                          silencioso: true,
                        ),
                        onTap: _abrirDetalle,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Cabecera de sprint: qué sprint se está mirando, su meta, sus fechas y cuánto
/// lleva hecho. El progreso cuenta el sprint entero, no lo filtrado.
class _SprintHeader extends StatelessWidget {
  final TicketsState state;

  const _SprintHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final sprint = state.selectedSprint;

    if (state.sprints.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Sin sprints en el orquestador: se muestran todos los tickets.',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            _MenuSprint(state: state),
          ],
        ),
      );
    }

    final total = state.sprintTotal;
    final hechos = state.sprintCompletados;
    final progreso = state.sprintProgreso;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SPRINT',
                style: GoogleFonts.firaCode(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accentBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: state.selectedSprintId,
                    isExpanded: true,
                    isDense: true,
                    dropdownColor: AppTheme.surfaceLight,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    items: [
                      for (final s in _sprintsOrdenados(state))
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            s.isActivo
                                ? '🔥 ${s.name}'
                                : '${s.isCerrado ? '🔒' : '📋'} ${s.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) {
                        context.read<TicketsCubit>().selectSprint(id);
                      }
                    },
                  ),
                ),
              ),
              if (sprint != null) ...[
                const SizedBox(width: 8),
                _Etiqueta(
                  texto: sprint.isCerrado
                      ? 'SOLO LECTURA'
                      : sprint.status.toUpperCase(),
                  color: sprint.isActivo
                      ? const Color(0xFF00FF66)
                      : sprint.isCerrado
                      ? AppTheme.textSecondary
                      : AppTheme.accentBlue,
                ),
              ],
              _MenuSprint(state: state),
            ],
          ),
          if (sprint?.goal != null && sprint!.goal!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sprint.goal!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70),
            ),
          ],
          if (sprint != null && sprint.periodo.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '📅 ${sprint.periodo}',
              style: GoogleFonts.firaCode(
                fontSize: 10,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$hechos de $total resueltos',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '$progreso%',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF00FF66),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : hechos / total,
              minHeight: 6,
              backgroundColor: AppTheme.background,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF00FF66)),
            ),
          ),
        ],
      ),
    );
  }

  /// El activo primero: es el que se mira el 90% de las veces.
  List<SprintModel> _sprintsOrdenados(TicketsState state) {
    final activo = state.activeSprint;
    if (activo == null) return state.sprints;
    return [activo, ...state.sprints.where((s) => s.id != activo.id)];
  }
}

/// Acciones de sprint: cerrar el activo (abriendo el siguiente y arrastrando lo
/// pendiente) y abrir uno nuevo. Vivían en el panel; desde que el tablero se
/// mudó al Jetson no había forma de cerrar un sprint desde ningún sitio.
class _MenuSprint extends StatelessWidget {
  final TicketsState state;

  const _MenuSprint({required this.state});

  @override
  Widget build(BuildContext context) {
    final sprint = state.selectedSprint;
    // Solo se cierra el que está activo: cerrar uno planificado no significa
    // nada, y uno cerrado ya lo está.
    final puedeCerrar = sprint != null && sprint.isActivo;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
      color: AppTheme.surfaceLight,
      tooltip: 'Acciones de sprint',
      onSelected: (accion) {
        if (accion == 'cerrar' && sprint != null) {
          _dialogoCerrar(context, sprint);
        } else if (accion == 'nuevo') {
          _dialogoNuevo(context);
        }
      },
      itemBuilder: (_) => [
        if (puedeCerrar)
          PopupMenuItem(
            value: 'cerrar',
            child: Text(
              '🏁 Cerrar ${sprint.name}',
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.white),
            ),
          ),
        PopupMenuItem(
          value: 'nuevo',
          child: Text(
            '✨ Nuevo sprint',
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.white),
          ),
        ),
      ],
    );
  }

  /// Lo que se va a arrastrar al siguiente sprint: ni hechos ni descartados.
  int _pendientes() => state.tickets
      .where((t) => t.status != 'hecho' && t.status != 'descartado')
      .length;

  void _dialogoCerrar(BuildContext context, SprintModel sprint) {
    final cubit = context.read<TicketsCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final nombre = TextEditingController(text: 'Sprint ${sprint.id + 1}');
    final meta = TextEditingController();
    final arrastre = _pendientes();

    showDialog(
      context: context,
      builder: (dialCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Cerrar ${sprint.name}',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                arrastre == 0
                    ? 'No queda nada pendiente: el sprint se cierra limpio.'
                    : 'Se pasarán $arrastre tickets sin terminar al sprint nuevo. '
                          'El sprint cerrado queda en solo lectura.',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nombre,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nombre del sprint nuevo',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: meta,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Meta del sprint nuevo (opcional)',
                ),
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
            onPressed: () async {
              Navigator.pop(dialCtx);
              final arrastrados = await cubit.closeSprint(
                sprintId: sprint.id,
                nextName: nombre.text.trim().isEmpty
                    ? null
                    : nombre.text.trim(),
                nextGoal: meta.text.trim().isEmpty ? null : meta.text.trim(),
              );
              // Si falló, el cubit ya emitió el error y la pantalla lo enseña.
              if (arrastrados == null) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    '${sprint.name} cerrado. $arrastrados tickets pasaron al sprint nuevo.',
                    style: GoogleFonts.outfit(),
                  ),
                  backgroundColor: AppTheme.primaryPurple,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPurple,
            ),
            child: const Text('Cerrar sprint'),
          ),
        ],
      ),
    );
  }

  void _dialogoNuevo(BuildContext context) {
    final cubit = context.read<TicketsCubit>();
    final nombre = TextEditingController();
    final meta = TextEditingController();

    showDialog(
      context: context,
      builder: (dialCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Nuevo sprint',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nace activo y pasa a recibir los tickets nuevos; el que estuviera '
                'activo vuelve a planificado.',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nombre,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: meta,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Meta (opcional)'),
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
              if (nombre.text.trim().isEmpty) return;
              Navigator.pop(dialCtx);
              cubit.createSprint(
                name: nombre.text.trim(),
                goal: meta.text.trim().isEmpty ? null : meta.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPurple,
            ),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }
}

/// Buscador + acceso a los filtros, con los que están puestos a la vista para
/// que nunca se quede uno activo sin que se note.
class _BarraFiltros extends StatelessWidget {
  final TicketsState state;
  final TextEditingController searchController;
  final VoidCallback onAbrirFiltros;
  final VoidCallback onLimpiar;

  const _BarraFiltros({
    required this.state,
    required this.searchController,
    required this.onAbrirFiltros,
    required this.onLimpiar,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TicketsCubit>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: searchController,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: Colors.white,
                    ),
                    onChanged: cubit.setQuery,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      hintText: 'Buscar por código o título…',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                      suffixIcon: state.query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () {
                                searchController.clear();
                                cubit.setQuery('');
                              },
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: state.activeFilterCount > 0,
                label: Text('${state.activeFilterCount}'),
                backgroundColor: AppTheme.primaryPurple,
                child: IconButton(
                  onPressed: onAbrirFiltros,
                  tooltip: 'Filtros',
                  icon: Icon(
                    Icons.tune_rounded,
                    color: state.hasFilters
                        ? AppTheme.primaryPurple
                        : AppTheme.accentBlue,
                  ),
                ),
              ),
            ],
          ),
          if (state.projectFilter != null ||
              state.areaFilter != null ||
              state.priorityFilter != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (state.projectFilter != null)
                          _ChipFiltro(
                            texto: state.projectFilter!,
                            color: AppTheme.accentBlue,
                            onRemove: () => cubit.setProjectFilter(null),
                          ),
                        if (state.areaFilter != null)
                          _ChipFiltro(
                            texto:
                                kAreaLabel[state.areaFilter!] ??
                                state.areaFilter!,
                            color: areaColor(state.areaFilter!),
                            onRemove: () => cubit.setAreaFilter(null),
                          ),
                        if (state.priorityFilter != null)
                          _ChipFiltro(
                            texto:
                                kPriorityLabel[state.priorityFilter!] ??
                                state.priorityFilter!,
                            color: priorityColor(state.priorityFilter!),
                            onRemove: () => cubit.setPriorityFilter(null),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onLimpiar,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Limpiar',
                      style: GoogleFonts.outfit(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GrupoFiltro extends StatelessWidget {
  final String titulo;

  /// (valor, etiqueta) de cada opción.
  final List<(String, String)> opciones;
  final String? seleccionada;
  final void Function(String?) onSelect;
  final Color Function(String)? colorDe;

  const _GrupoFiltro({
    required this.titulo,
    required this.opciones,
    required this.seleccionada,
    required this.onSelect,
    this.colorDe,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            titulo.toUpperCase(),
            style: GoogleFonts.firaCode(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (valor, etiqueta) in opciones)
              ChoiceChip(
                label: Text(
                  etiqueta,
                  style: GoogleFonts.firaCode(fontSize: 11),
                ),
                selected: seleccionada == valor,
                showCheckmark: false,
                backgroundColor: AppTheme.surfaceLight,
                selectedColor: (colorDe?.call(valor) ?? AppTheme.primaryPurple)
                    .withValues(alpha: 0.30),
                // Tocar la opción ya elegida la quita: es el gesto natural para
                // "quítame este filtro" sin tener que ir a otro botón.
                onSelected: (sel) => onSelect(sel ? valor : null),
              ),
          ],
        ),
      ],
    );
  }
}

class _ColumnaTickets extends StatelessWidget {
  final List<TicketModel> tickets;
  final String vacio;
  final Future<void> Function() onRefresh;
  final void Function(TicketModel) onTap;

  const _ColumnaTickets({
    required this.tickets,
    required this.vacio,
    required this.onRefresh,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.accentBlue,
      backgroundColor: AppTheme.surface,
      child: tickets.isEmpty
          // Con una lista vacía hace falta que scrollee igual, o no se puede
          // tirar para refrescar.
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text(
                      vacio,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(color: AppTheme.textSecondary),
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
              itemCount: tickets.length,
              itemBuilder: (context, index) => _TarjetaTicket(
                ticket: tickets[index],
                onTap: () => onTap(tickets[index]),
              ),
            ),
    );
  }
}

class _TarjetaTicket extends StatelessWidget {
  final TicketModel ticket;
  final VoidCallback onTap;

  const _TarjetaTicket({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.border.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: priorityColor(ticket.priority),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ticket.code,
                    style: GoogleFonts.firaCode(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                  const Spacer(),
                  if (ticket.area != null)
                    _Etiqueta(
                      texto: kAreaLabel[ticket.area!] ?? ticket.area!,
                      color: areaColor(ticket.area!),
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
              if (ticket.description != null &&
                  ticket.description!.isNotEmpty) ...[
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
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color color;

  const _Etiqueta({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto.toUpperCase(),
        style: GoogleFonts.firaCode(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  final int valor;
  final Color color;

  const _Contador({required this.valor, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$valor',
        style: GoogleFonts.firaCode(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _ChipFiltro extends StatelessWidget {
  final String texto;
  final Color color;
  final VoidCallback onRemove;

  const _ChipFiltro({
    required this.texto,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(
        texto,
        style: GoogleFonts.firaCode(fontSize: 10, color: color),
      ),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      deleteIcon: Icon(Icons.close_rounded, size: 14, color: color),
      onDeleted: onRemove,
    );
  }
}

class _Reintentar extends StatelessWidget {
  final String mensaje;
  final VoidCallback onRetry;

  const _Reintentar({required this.mensaje, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
