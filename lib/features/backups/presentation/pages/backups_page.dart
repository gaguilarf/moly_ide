import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/backups/presentation/cubit/backups_cubit.dart';
import 'package:moly_ide/features/backups/presentation/cubit/backups_state.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';

class BackupsPage extends StatefulWidget {
  const BackupsPage({super.key});

  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  @override
  void initState() {
    super.initState();
    context.read<BackupsCubit>().loadBackups();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < suffixes.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Backups por Proyecto', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_rounded, color: AppTheme.accentBlue),
            tooltip: 'Actualizar App',
            onPressed: () => UpdateDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentBlue),
            tooltip: 'Recargar',
            onPressed: () => context.read<BackupsCubit>().loadBackups(),
          ),
        ],
      ),
      body: BlocBuilder<BackupsCubit, BackupsState>(
        builder: (context, state) {
          if (state.status == BackupsStatus.loading) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.accentBlue));
          }

          final overview = state.overview;
          if (overview == null || overview.databases.isEmpty) {
            return Center(
              child: Text('No hay información de backups disponible.', style: GoogleFonts.outfit(color: AppTheme.textSecondary)),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header Summary Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.surface, AppTheme.surfaceLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_done_rounded, color: Color(0xFF00FF66), size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(overview.serverName, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                          Text('Estrategia GFS (Daily / Weekly / Monthly)', style: GoogleFonts.firaCode(fontSize: 11, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Text('BASES DE DATOS RESPALDADAS', style: GoogleFonts.firaCode(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
              const SizedBox(height: 10),

              ...overview.databases.map((db) {
                final isHealthy = db.isHealthy;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isHealthy ? const Color(0xFF00FF66).withOpacity(0.3) : const Color(0xFFFF9900).withOpacity(0.4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              db.database,
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isHealthy ? const Color(0xFF00FF66) : const Color(0xFFFF9900)).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isHealthy ? 'SANO (<26H)' : 'DESACTUALIZADO',
                                style: GoogleFonts.firaCode(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isHealthy ? const Color(0xFF00FF66) : const Color(0xFFFF9900),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (db.latestBackup != null) ...[
                          Text(
                            'Último dump: ${db.latestBackup!.filename}',
                            style: GoogleFonts.firaCode(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tamaño: ${_formatBytes(db.latestBackup!.sizeBytes)} • ${db.totalDumps} copias guardadas',
                            style: GoogleFonts.firaCode(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ] else
                          Text('Sin dumps registrados.', style: GoogleFonts.firaCode(fontSize: 11, color: const Color(0xFFFF3366))),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
