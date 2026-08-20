import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/updates/presentation/cubit/update_cubit.dart';
import 'package:moly_ide/features/updates/presentation/cubit/update_state.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BlocProvider(
        create: (context) => UpdateCubit(),
        child: const UpdateDialog(),
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = context.read<UpdateCubit>().state.updateUrl;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpdateCubit, UpdateState>(
      builder: (context, state) {
        final isDownloading = state.status == UpdateStatus.downloading;
        final isSuccess = state.status == UpdateStatus.success;
        final isUpToDate = state.isUpToDate;
        final isChecking = state.isCheckingVersion;

        return Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: AppTheme.border, width: 1.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: AppTheme.accentBlue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Actualización de la App',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              'Instalada: v${state.currentVersion}',
                              style: GoogleFonts.firaCode(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            if (state.latestVersion != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '• Servidor: v${state.latestVersion}',
                                style: GoogleFonts.firaCode(
                                  fontSize: 11,
                                  color: isUpToDate
                                      ? const Color(0xFF00FF66)
                                      : const Color(0xFFFF9900),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: isDownloading
                        ? null
                        : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Version Comparison Status Card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isUpToDate
                      ? const Color(0xFF00FF66).withOpacity(0.1)
                      : (state.latestVersion != null
                            ? const Color(0xFFFF9900).withOpacity(0.1)
                            : AppTheme.surfaceLight),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isUpToDate
                        ? const Color(0xFF00FF66).withOpacity(0.4)
                        : (state.latestVersion != null
                              ? const Color(0xFFFF9900).withOpacity(0.4)
                              : AppTheme.border),
                  ),
                ),
                child: Row(
                  children: [
                    if (isChecking)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: AppTheme.accentBlue,
                          strokeWidth: 2,
                        ),
                      )
                    else if (isUpToDate)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF00FF66),
                        size: 18,
                      )
                    else if (state.latestVersion != null)
                      const Icon(
                        Icons.new_releases_rounded,
                        color: Color(0xFFFF9900),
                        size: 18,
                      )
                    else
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.accentBlue,
                        size: 18,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isChecking
                            ? 'Comprobando última versión en el servidor...'
                            : (isUpToDate
                                  ? 'Estás en la última versión disponible (v${state.currentVersion}).'
                                  : (state.latestVersion != null
                                        ? '¡Nueva versión disponible (v${state.latestVersion})!'
                                        : state.statusMessage)),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: isUpToDate || state.latestVersion != null
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isUpToDate
                              ? const Color(0xFF00FF66)
                              : (state.latestVersion != null
                                    ? const Color(0xFFFF9900)
                                    : Colors.white),
                        ),
                      ),
                    ),
                    if (!isDownloading)
                      IconButton(
                        icon: const Icon(
                          Icons.sync_rounded,
                          size: 16,
                          color: AppTheme.accentBlue,
                        ),
                        tooltip: 'Volver a comprobar',
                        onPressed: () =>
                            context.read<UpdateCubit>().checkForUpdates(
                              urlOverride: _urlController.text.trim(),
                            ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Server URL textfield
              Text(
                'URL del Servidor de Descargas:',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                enabled: !isDownloading,
                style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText:
                      'https://panel.ragnargroup.app/updates/app-release.apk',
                  filled: true,
                  fillColor: AppTheme.surfaceLight,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (val) =>
                    context.read<UpdateCubit>().setUpdateUrl(val),
              ),
              const SizedBox(height: 12),

              // Progress Bar (if downloading)
              if (isDownloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: state.progress > 0 ? state.progress : null,
                    backgroundColor: AppTheme.surfaceLight,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.accentBlue,
                    ),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  state.statusMessage,
                  style: GoogleFonts.firaCode(
                    fontSize: 11,
                    color: AppTheme.accentBlue,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Action Buttons
              if (isSuccess) ...[
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF66),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ElevatedButton.icon(
                    icon: const Icon(
                      Icons.install_mobile_rounded,
                      color: Colors.black,
                    ),
                    label: Text(
                      'INSTALAR APK DESCARGADO',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () =>
                        context.read<UpdateCubit>().openExistingApk(),
                  ),
                ),
              ] else ...[
                // Main CTA: Disabled if isUpToDate == true
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: (isUpToDate || isDownloading)
                        ? null
                        : AppTheme.purpleBlueGradient,
                    color: (isUpToDate || isDownloading)
                        ? AppTheme.surfaceLight
                        : null,
                    borderRadius: BorderRadius.circular(10),
                    border: isUpToDate
                        ? Border.all(color: AppTheme.border)
                        : null,
                  ),
                  child: ElevatedButton.icon(
                    icon: isDownloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            isUpToDate
                                ? Icons.check_circle_outline_rounded
                                : Icons.download_rounded,
                            color: isUpToDate
                                ? AppTheme.textSecondary
                                : Colors.white,
                          ),
                    label: Text(
                      isDownloading
                          ? 'DESCARGANDO...'
                          : (isUpToDate
                                ? 'ESTÁS EN LA ÚLTIMA VERSIÓN'
                                : (state.latestVersion != null
                                      ? 'DESCARGAR E INSTALAR V${state.latestVersion}'
                                      : 'DESCARGAR E INSTALAR')),
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: isUpToDate
                            ? AppTheme.textSecondary
                            : Colors.white,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      disabledForegroundColor: AppTheme.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: (isUpToDate || isDownloading)
                        ? null
                        : () {
                            context.read<UpdateCubit>().downloadAndInstall(
                              urlOverride: _urlController.text.trim(),
                            );
                          },
                  ),
                ),

                // Subtle option if user is up to date but wants to force reinstall
                if (isUpToDate && !isDownloading) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        context.read<UpdateCubit>().downloadAndInstall(
                          urlOverride: _urlController.text.trim(),
                        );
                      },
                      child: Text(
                        'Reinstalar versión de todos modos',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
