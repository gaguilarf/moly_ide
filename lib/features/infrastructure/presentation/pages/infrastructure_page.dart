import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/auth/presentation/widgets/boton_cerrar_sesion.dart';
import 'package:moly_ide/features/infrastructure/presentation/cubit/infra_cubit.dart';
import 'package:moly_ide/features/infrastructure/presentation/cubit/infra_state.dart';
import 'package:moly_ide/features/monitor/presentation/pages/resource_monitor_page.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';

class InfrastructurePage extends StatefulWidget {
  const InfrastructurePage({super.key});

  @override
  State<InfrastructurePage> createState() => _InfrastructurePageState();
}

class _InfrastructurePageState extends State<InfrastructurePage> {
  @override
  void initState() {
    super.initState();
    context.read<InfraCubit>().loadServerStatus();
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'aplicacion':
        return AppTheme.accentBlue;
      case 'datos':
        return const Color(0xFFFF9900);
      case 'observabilidad':
        return AppTheme.primaryPurple;
      case 'seguridad':
        return const Color(0xFFFF3366);
      case 'sistema':
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Monitor de Puertos',
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
            icon: const Icon(Icons.speed_rounded, color: AppTheme.accentBlue),
            tooltip: 'Monitor de recursos',
            // Se empuja como ruta y no como pestana a proposito: la pagina
            // consulta el VPS por SSH cada 3 s mientras esta montada, y en el
            // IndexedStack de la navegacion seguiria haciendolo sin verse.
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ResourceMonitorPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentBlue),
            tooltip: 'Recargar',
            onPressed: () => context.read<InfraCubit>().loadServerStatus(),
          ),
          const BotonCerrarSesion(),
        ],
      ),
      body: BlocBuilder<InfraCubit, InfraState>(
        builder: (context, state) {
          return Column(
            children: [
              // Server Node Selector Chips
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: AppTheme.surface,
                child: Row(
                  children: [
                    Text(
                      'SERVIDOR:',
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: Text(
                        'VPS Brittany',
                        style: GoogleFonts.outfit(fontSize: 12),
                      ),
                      selected: state.selectedNode == 'vps-brittany',
                      selectedColor: AppTheme.primaryPurple.withOpacity(0.4),
                      onSelected: (selected) {
                        if (selected)
                          context.read<InfraCubit>().loadServerStatus(
                            node: 'vps-brittany',
                          );
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(
                        'Jetson',
                        style: GoogleFonts.outfit(fontSize: 12),
                      ),
                      selected: state.selectedNode == 'jetson',
                      selectedColor: AppTheme.primaryPurple.withOpacity(0.4),
                      onSelected: (selected) {
                        if (selected)
                          context.read<InfraCubit>().loadServerStatus(
                            node: 'jetson',
                          );
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(
                        'Personal',
                        style: GoogleFonts.outfit(fontSize: 12),
                      ),
                      selected: state.selectedNode == 'vps-personal',
                      selectedColor: AppTheme.primaryPurple.withOpacity(0.4),
                      onSelected: (selected) {
                        if (selected)
                          context.read<InfraCubit>().loadServerStatus(
                            node: 'vps-personal',
                          );
                      },
                    ),
                  ],
                ),
              ),

              if (state.status == InfraStatus.loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.accentBlue,
                    ),
                  ),
                )
              else if (state.serverStatus != null) ...[
                // Server Summary Card
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.serverStatus!.isReachable
                              ? const Color(0xFF00FF66)
                              : const Color(0xFFFF3366),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.serverStatus!.serverName,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Host: ${state.serverStatus!.serverHost} • ${state.serverStatus!.ports.length} puertos a la escucha',
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

                // Ports List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: state.serverStatus!.ports.length,
                    itemBuilder: (context, idx) {
                      final port = state.serverStatus!.ports[idx];
                      final catColor = _getCategoryColor(port.category);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: AppTheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: AppTheme.border.withOpacity(0.5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              // Port Number Badge
                              Container(
                                width: 56,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: catColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: catColor, width: 1),
                                ),
                                child: Text(
                                  '${port.port}',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.firaCode(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: catColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      port.serviceName ??
                                          'Servicio sin catalogar',
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: port.serviceName != null
                                            ? Colors.white
                                            : const Color(0xFFFF9900),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Escucha en: ${port.addresses.join(", ")}',
                                      style: GoogleFonts.firaCode(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (port.isExposed)
                                Tooltip(
                                  message: 'Expuesto a internet (0.0.0.0 / ::)',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFFF3366,
                                      ).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'EXPUESTO',
                                      style: GoogleFonts.firaCode(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFFFF3366),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
