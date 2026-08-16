import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/auth/presentation/widgets/boton_cerrar_sesion.dart';
import 'package:moly_ide/features/explorer_readonly/data/models/file_models.dart';
import 'package:moly_ide/features/explorer_readonly/presentation/cubit/readonly_explorer_cubit.dart';
import 'package:moly_ide/features/explorer_readonly/presentation/cubit/readonly_explorer_state.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_cubit.dart';

class ReadonlyExplorerPage extends StatefulWidget {
  const ReadonlyExplorerPage({super.key});

  @override
  State<ReadonlyExplorerPage> createState() => _ReadonlyExplorerPageState();
}

class _ReadonlyExplorerPageState extends State<ReadonlyExplorerPage> {
  @override
  void initState() {
    super.initState();
    context.read<ReadonlyExplorerCubit>().listDirectory('/root');
  }

  void _openFileViewer(BuildContext context, RemoteFileItem file) {
    context.read<ReadonlyExplorerCubit>().readConfigFile(file.path, file.name);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bSheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return BlocBuilder<ReadonlyExplorerCubit, ReadonlyExplorerState>(
              builder: (context, state) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.textSecondary.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            color: Color(0xFFFF9900),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${file.name} (Solo Lectura)',
                              style: GoogleFonts.firaCode(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppTheme.textSecondary,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: AppTheme.border, height: 1),

                    // Quick Action: Pedir cambio a Claude
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          final prompt =
                              'Por favor edita el archivo "${file.path}" para: ';
                          context.read<ClaudeCubit>().launchTask(
                            title: 'Editar ${file.name}',
                            prompt: prompt,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Comando de edición enviado a Claude...',
                                style: GoogleFonts.outfit(),
                              ),
                              backgroundColor: AppTheme.primaryPurple,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.surfaceLight,
                          side: const BorderSide(color: AppTheme.primaryPurple),
                        ),
                        icon: const Icon(
                          Icons.auto_fix_high_rounded,
                          color: AppTheme.accentBlue,
                          size: 16,
                        ),
                        label: Text(
                          'PEDIR CAMBIO A CLAUDE',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: state.openFileContent == null
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppTheme.accentBlue,
                              ),
                            )
                          : Container(
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D0D12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: SingleChildScrollView(
                                controller: scrollController,
                                child: SelectableText(
                                  state.openFileContent!,
                                  style: GoogleFonts.firaCode(
                                    fontSize: 12,
                                    color: const Color(0xFF00FF66),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Explorador Solo Lectura',
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
            icon: const Icon(
              Icons.arrow_upward_rounded,
              color: AppTheme.accentBlue,
            ),
            tooltip: 'Subir nivel',
            onPressed: () => context.read<ReadonlyExplorerCubit>().navigateUp(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentBlue),
            tooltip: 'Recargar',
            onPressed: () {
              final cur = context
                  .read<ReadonlyExplorerCubit>()
                  .state
                  .currentPath;
              context.read<ReadonlyExplorerCubit>().listDirectory(cur);
            },
          ),
          const BotonCerrarSesion(),
        ],
      ),
      body: BlocBuilder<ReadonlyExplorerCubit, ReadonlyExplorerState>(
        builder: (context, state) {
          return Column(
            children: [
              // Path Breadcrumb Bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: AppTheme.surface,
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_open_rounded,
                      color: AppTheme.accentBlue,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.currentPath,
                        style: GoogleFonts.firaCode(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              if (state.status == ReadonlyExplorerStatus.loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.accentBlue,
                    ),
                  ),
                )
              else
                Expanded(
                  child: state.files.isEmpty
                      ? Center(
                          child: Text(
                            'Directorio vacío.',
                            style: GoogleFonts.outfit(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: state.files.length,
                          itemBuilder: (context, idx) {
                            final item = state.files[idx];
                            final isEnv = item.name.contains('.env');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              color: AppTheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isEnv
                                      ? const Color(0xFF00FF66).withOpacity(0.4)
                                      : AppTheme.border.withOpacity(0.4),
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  item.isDir
                                      ? Icons.folder_rounded
                                      : (isEnv
                                            ? Icons.key_rounded
                                            : Icons.insert_drive_file_rounded),
                                  color: item.isDir
                                      ? AppTheme.accentBlue
                                      : (isEnv
                                            ? const Color(0xFF00FF66)
                                            : AppTheme.textSecondary),
                                  size: 22,
                                ),
                                title: Text(
                                  item.name,
                                  style: GoogleFonts.firaCode(
                                    fontSize: 13,
                                    fontWeight: item.isDir || isEnv
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isEnv
                                        ? const Color(0xFF00FF66)
                                        : Colors.white,
                                  ),
                                ),
                                subtitle: item.modifiedAt != null
                                    ? Text(
                                        item.modifiedAt!,
                                        style: GoogleFonts.firaCode(
                                          fontSize: 10,
                                          color: AppTheme.textSecondary,
                                        ),
                                      )
                                    : null,
                                trailing: item.isDir
                                    ? const Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppTheme.textSecondary,
                                        size: 18,
                                      )
                                    : null,
                                onTap: () {
                                  if (item.isDir) {
                                    context
                                        .read<ReadonlyExplorerCubit>()
                                        .listDirectory(item.path);
                                  } else {
                                    _openFileViewer(context, item);
                                  }
                                },
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
